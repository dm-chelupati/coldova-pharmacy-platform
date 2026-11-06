USE [CaldovaBenefits];
GO

GRANT VIEW DEFINITION ON OBJECT::dbo.MemberBenefits TO [caldova_sre_automation];
GO

CREATE OR ALTER PROCEDURE dbo.TerminateStalledBenefitsSync
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @minimumAgeSeconds int = 120;
    DECLARE @sessionId int;
    DECLARE @matchingSessions int;
    DECLARE @transactionAgeSeconds int;
    DECLARE @blockedRequests int;
    DECLARE @utcHour int = DATEPART(HOUR, SYSUTCDATETIME());

    IF @utcHour < 0 OR @utcHour >= 12
    BEGIN
        SELECT
            N'refused' AS status,
            N'outside_approved_overnight_window' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    SELECT
        @matchingSessions = COUNT(*),
        @sessionId = MIN(session_id)
    FROM sys.dm_exec_sessions
    WHERE login_name = N'caldova_nightly_benefits_sync'
      AND program_name = N'caldova-nightly-benefits-sync'
      AND open_transaction_count > 0;

    IF @matchingSessions <> 1
    BEGIN
        SELECT
            N'refused' AS status,
            IIF(@matchingSessions = 0, N'no_matching_sync_session', N'multiple_matching_sync_sessions') AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    SELECT
        @transactionAgeSeconds =
            DATEDIFF(SECOND, MIN(active_transaction.transaction_begin_time), SYSUTCDATETIME())
    FROM sys.dm_tran_session_transactions AS session_transaction
    INNER JOIN sys.dm_tran_active_transactions AS active_transaction
        ON active_transaction.transaction_id = session_transaction.transaction_id
    WHERE session_transaction.session_id = @sessionId;

    IF COALESCE(@transactionAgeSeconds, 0) < @minimumAgeSeconds
    BEGIN
        SELECT
            N'refused' AS status,
            N'transaction_below_approved_age' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM sys.dm_exec_requests
        WHERE session_id = @sessionId
          AND COALESCE(wait_type, N'') <> N'WAITFOR'
    )
    BEGIN
        SELECT
            N'refused' AS status,
            N'sync_session_is_not_stalled' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.dm_tran_locks AS transaction_lock
        LEFT JOIN sys.partitions AS locked_partition
            ON locked_partition.hobt_id = transaction_lock.resource_associated_entity_id
        WHERE transaction_lock.request_session_id = @sessionId
          AND transaction_lock.request_status = N'GRANT'
          AND
          (
              transaction_lock.resource_associated_entity_id = OBJECT_ID(N'dbo.MemberBenefits')
              OR locked_partition.object_id = OBJECT_ID(N'dbo.MemberBenefits')
          )
    )
    BEGIN
        SELECT
            N'refused' AS status,
            N'critical_benefits_table_is_not_locked' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    SELECT @blockedRequests = COUNT(*)
    FROM sys.dm_exec_requests AS waiting_request
    INNER JOIN sys.dm_exec_sessions AS waiting_session
        ON waiting_session.session_id = waiting_request.session_id
    WHERE waiting_request.blocking_session_id = @sessionId
      AND waiting_request.wait_type LIKE N'LCK_M_%'
      AND DB_NAME(waiting_request.database_id) = N'CaldovaBenefits'
      AND waiting_session.login_name = N'caldova_benefits_app'
      AND waiting_session.program_name LIKE N'caldova-benefits-api%';

    IF COALESCE(@blockedRequests, 0) = 0
    BEGIN
        SELECT
            N'refused' AS status,
            N'no_customer_payment_query_is_blocked' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    DECLARE @killCommand nvarchar(32) =
        N'KILL ' + CONVERT(nvarchar(10), @sessionId) + N';';
    EXEC sp_executesql @killCommand;

    SELECT
        N'terminated' AS status,
        N'all_guardrails_passed' AS reason,
        @sessionId AS terminated_session_id,
        @transactionAgeSeconds AS transaction_age_seconds,
        @blockedRequests AS blocked_request_count;
END;
GO

GRANT EXECUTE ON dbo.TerminateStalledBenefitsSync TO [caldova_sre_automation];
GO

CREATE OR ALTER PROCEDURE dbo.TerminateApprovedDemoTransaction
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @minimumAgeSeconds int = 120;
    DECLARE @sessionId int;
    DECLARE @matchingSessions int;
    DECLARE @transactionAgeSeconds int;
    DECLARE @blockedRequests int;

    SELECT
        @matchingSessions = COUNT(*),
        @sessionId = MIN(session_id)
    FROM sys.dm_exec_sessions
    WHERE login_name = N'caldova_transaction_holder'
      AND program_name LIKE N'SQLCMD%'
      AND open_transaction_count > 0;

    IF @matchingSessions <> 1
    BEGIN
        SELECT
            N'refused' AS status,
            IIF(@matchingSessions = 0, N'no_matching_demo_transaction', N'multiple_matching_demo_transactions') AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    SELECT
        @transactionAgeSeconds =
            DATEDIFF(SECOND, MIN(active_transaction.transaction_begin_time), SYSUTCDATETIME())
    FROM sys.dm_tran_session_transactions AS session_transaction
    INNER JOIN sys.dm_tran_active_transactions AS active_transaction
        ON active_transaction.transaction_id = session_transaction.transaction_id
    WHERE session_transaction.session_id = @sessionId;

    IF COALESCE(@transactionAgeSeconds, 0) < @minimumAgeSeconds
    BEGIN
        SELECT
            N'refused' AS status,
            N'transaction_below_approved_age' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.dm_exec_requests
        WHERE session_id = @sessionId
          AND wait_type = N'WAITFOR'
    )
    BEGIN
        SELECT
            N'refused' AS status,
            N'demo_transaction_is_not_waiting_for_observation' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.dm_tran_locks AS transaction_lock
        LEFT JOIN sys.partitions AS locked_partition
            ON locked_partition.hobt_id = transaction_lock.resource_associated_entity_id
        WHERE transaction_lock.request_session_id = @sessionId
          AND transaction_lock.request_status = N'GRANT'
          AND
          (
              transaction_lock.resource_associated_entity_id = OBJECT_ID(N'dbo.MemberBenefits')
              OR locked_partition.object_id = OBJECT_ID(N'dbo.MemberBenefits')
          )
    )
    BEGIN
        SELECT
            N'refused' AS status,
            N'critical_benefits_table_is_not_locked' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    SELECT @blockedRequests = COUNT(*)
    FROM sys.dm_exec_requests AS waiting_request
    INNER JOIN sys.dm_exec_sessions AS waiting_session
        ON waiting_session.session_id = waiting_request.session_id
    WHERE waiting_request.blocking_session_id = @sessionId
      AND waiting_request.wait_type LIKE N'LCK_M_%'
      AND DB_NAME(waiting_request.database_id) = N'CaldovaBenefits'
      AND waiting_session.login_name = N'caldova_benefits_app'
      AND waiting_session.program_name LIKE N'caldova-benefits-api%';

    IF COALESCE(@blockedRequests, 0) = 0
    BEGIN
        SELECT
            N'refused' AS status,
            N'no_customer_payment_query_is_blocked' AS reason,
            CAST(NULL AS int) AS terminated_session_id;
        RETURN;
    END;

    DECLARE @killCommand nvarchar(32) =
        N'KILL ' + CONVERT(nvarchar(10), @sessionId) + N';';
    EXEC sp_executesql @killCommand;

    SELECT
        N'terminated' AS status,
        N'all_guardrails_passed' AS reason,
        @sessionId AS terminated_session_id,
        @transactionAgeSeconds AS transaction_age_seconds,
        @blockedRequests AS blocked_request_count;
END;
GO

GRANT EXECUTE ON dbo.TerminateApprovedDemoTransaction TO [caldova_sre_automation];
GO
