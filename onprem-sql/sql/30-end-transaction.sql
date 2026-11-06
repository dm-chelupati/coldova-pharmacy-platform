USE [CaldovaBenefits];
GO

SET NOCOUNT ON;

DECLARE @session_id smallint;
DECLARE @session_count int;

SELECT
    @session_count = COUNT(*),
    @session_id = MAX(session_id)
FROM sys.dm_exec_sessions
WHERE login_name = N'caldova_transaction_holder'
  AND program_name LIKE N'SQLCMD%';

IF @session_count = 0
BEGIN
    PRINT N'No Caldova transaction-holder session is active.';
    RETURN;
END;

IF @session_count > 1
BEGIN
    THROW 51000, 'Multiple Caldova transaction-holder sessions are active; refusing automatic selection.', 1;
END;

DECLARE @kill_command nvarchar(32) = N'KILL ' + CONVERT(nvarchar(10), @session_id);
EXEC sys.sp_executesql @kill_command;

PRINT N'The Caldova transaction-holder session was terminated. SQL Server will roll back its open transaction.';
GO
