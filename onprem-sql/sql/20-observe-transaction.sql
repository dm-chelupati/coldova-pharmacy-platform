SELECT
    transaction_holder.session_id AS transaction_session_id,
    transaction_holder.login_name AS transaction_login,
    transaction_holder.program_name AS transaction_program,
    transaction_holder.open_transaction_count,
    active_transaction.transaction_begin_time,
    DATEDIFF(MINUTE, active_transaction.transaction_begin_time, SYSUTCDATETIME()) AS transaction_age_minutes,
    blocked_request.session_id AS blocked_session_id,
    blocked_session.login_name AS blocked_login,
    blocked_session.program_name AS blocked_program,
    DB_NAME(blocked_request.database_id) AS blocked_database,
    blocked_request.wait_type,
    blocked_request.wait_time AS wait_time_ms
FROM sys.dm_exec_sessions AS transaction_holder
INNER JOIN sys.dm_exec_requests AS blocked_request
    ON blocked_request.blocking_session_id = transaction_holder.session_id
INNER JOIN sys.dm_exec_sessions AS blocked_session
    ON blocked_session.session_id = blocked_request.session_id
INNER JOIN sys.dm_tran_session_transactions AS session_transaction
    ON session_transaction.session_id = transaction_holder.session_id
INNER JOIN sys.dm_tran_active_transactions AS active_transaction
    ON active_transaction.transaction_id = session_transaction.transaction_id
WHERE transaction_holder.login_name = N'caldova_transaction_holder'
  AND transaction_holder.program_name = N'SQLCMD'
ORDER BY blocked_request.wait_time DESC;
GO
