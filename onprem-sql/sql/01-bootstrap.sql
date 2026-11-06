:setvar DatabaseName "CaldovaBenefits"

USE [master];
GO

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    CREATE DATABASE [$(DatabaseName)];
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'caldova_benefits_app')
BEGIN
    CREATE LOGIN [caldova_benefits_app]
        WITH PASSWORD = N'$(BenefitsAppPassword)', CHECK_POLICY = ON;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'caldova_transaction_holder')
BEGIN
    CREATE LOGIN [caldova_transaction_holder]
        WITH PASSWORD = N'$(TransactionHolderPassword)', CHECK_POLICY = ON;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'caldova_nightly_benefits_sync')
BEGIN
    CREATE LOGIN [caldova_nightly_benefits_sync]
        WITH PASSWORD = N'$(NightlySyncPassword)', CHECK_POLICY = ON;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'caldova_sre_reader')
BEGIN
    CREATE LOGIN [caldova_sre_reader]
        WITH PASSWORD = N'$(SreReaderPassword)', CHECK_POLICY = ON;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'caldova_sre_automation')
BEGIN
    CREATE LOGIN [caldova_sre_automation]
        WITH PASSWORD = N'$(SreAutomationPassword)', CHECK_POLICY = ON;
END;
GO

GRANT VIEW SERVER STATE TO [caldova_sre_reader];
GRANT VIEW SERVER STATE, ALTER ANY CONNECTION TO [caldova_sre_automation];
GO

USE [$(DatabaseName)];
GO

IF OBJECT_ID(N'dbo.MemberBenefits', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MemberBenefits
    (
        MemberId int NOT NULL
            CONSTRAINT PK_MemberBenefits PRIMARY KEY,
        IsEligible bit NOT NULL,
        PlanName nvarchar(100) NOT NULL,
        RxGroup nvarchar(32) NOT NULL,
        CopayAmount decimal(10, 2) NOT NULL,
        LastVerifiedAt datetime2(0) NOT NULL
            CONSTRAINT DF_MemberBenefits_LastVerifiedAt DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'dbo.PharmacyProducts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PharmacyProducts
    (
        ProductId int NOT NULL
            CONSTRAINT PK_PharmacyProducts PRIMARY KEY,
        ProductName nvarchar(120) NOT NULL,
        Category nvarchar(80) NOT NULL,
        Price decimal(10, 2) NOT NULL,
        Availability nvarchar(40) NOT NULL,
        Badge nvarchar(4) NOT NULL,
        DisplayOrder int NOT NULL,
        IsActive bit NOT NULL
            CONSTRAINT DF_PharmacyProducts_IsActive DEFAULT 1
    );
END;
GO

MERGE dbo.MemberBenefits AS target
USING
(
    VALUES
        (1001, CAST(1 AS bit), N'Caldova Plus', N'RX-2048', CAST(10.00 AS decimal(10, 2))),
        (1002, CAST(1 AS bit), N'Caldova Essential', N'RX-1024', CAST(18.00 AS decimal(10, 2))),
        (1003, CAST(0 AS bit), N'Coverage review', N'RX-REVIEW', CAST(0.00 AS decimal(10, 2)))
) AS source (MemberId, IsEligible, PlanName, RxGroup, CopayAmount)
ON target.MemberId = source.MemberId
WHEN MATCHED THEN
    UPDATE SET
        IsEligible = source.IsEligible,
        PlanName = source.PlanName,
        RxGroup = source.RxGroup,
        CopayAmount = source.CopayAmount,
        LastVerifiedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (MemberId, IsEligible, PlanName, RxGroup, CopayAmount)
    VALUES (source.MemberId, source.IsEligible, source.PlanName, source.RxGroup, source.CopayAmount);
GO

MERGE dbo.PharmacyProducts AS target
USING
(
    VALUES
        (101, N'Cold & Flu Relief', N'Health essentials', CAST(12.49 AS decimal(10, 2)), N'In stock', N'CF', 1),
        (102, N'Daily Multivitamin', N'Vitamins', CAST(18.99 AS decimal(10, 2)), N'In stock', N'DV', 2),
        (103, N'Digital Thermometer', N'Home health', CAST(24.50 AS decimal(10, 2)), N'Low stock', N'DT', 3),
        (104, N'Allergy Relief', N'Health essentials', CAST(15.75 AS decimal(10, 2)), N'In stock', N'AR', 4),
        (105, N'Hydrating Skin Care', N'Personal care', CAST(21.00 AS decimal(10, 2)), N'In stock', N'HS', 5),
        (106, N'First Aid Kit', N'Home health', CAST(32.95 AS decimal(10, 2)), N'In stock', N'FA', 6)
) AS source (ProductId, ProductName, Category, Price, Availability, Badge, DisplayOrder)
ON target.ProductId = source.ProductId
WHEN MATCHED THEN
    UPDATE SET
        ProductName = source.ProductName,
        Category = source.Category,
        Price = source.Price,
        Availability = source.Availability,
        Badge = source.Badge,
        DisplayOrder = source.DisplayOrder,
        IsActive = 1
WHEN NOT MATCHED THEN
    INSERT (ProductId, ProductName, Category, Price, Availability, Badge, DisplayOrder)
    VALUES
        (source.ProductId, source.ProductName, source.Category, source.Price, source.Availability, source.Badge, source.DisplayOrder);
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'caldova_benefits_app')
    CREATE USER [caldova_benefits_app] FOR LOGIN [caldova_benefits_app];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'caldova_transaction_holder')
    CREATE USER [caldova_transaction_holder] FOR LOGIN [caldova_transaction_holder];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'caldova_nightly_benefits_sync')
    CREATE USER [caldova_nightly_benefits_sync] FOR LOGIN [caldova_nightly_benefits_sync];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'caldova_sre_reader')
    CREATE USER [caldova_sre_reader] FOR LOGIN [caldova_sre_reader];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'caldova_sre_automation')
    CREATE USER [caldova_sre_automation] FOR LOGIN [caldova_sre_automation];
GO

GRANT SELECT ON dbo.MemberBenefits TO [caldova_benefits_app];
GRANT SELECT ON dbo.PharmacyProducts TO [caldova_benefits_app];
GRANT SELECT, UPDATE, ALTER ON dbo.MemberBenefits TO [caldova_transaction_holder];
GRANT SELECT, UPDATE ON dbo.MemberBenefits TO [caldova_nightly_benefits_sync];
GRANT SELECT ON dbo.MemberBenefits TO [caldova_sre_reader];
GRANT SELECT ON dbo.PharmacyProducts TO [caldova_sre_reader];
GO

CREATE OR ALTER PROCEDURE dbo.GetOperationsTransactionActivity
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        transaction_holder.session_id AS transaction_session_id,
        transaction_holder.login_name AS transaction_login,
        transaction_holder.program_name AS transaction_program,
        transaction_holder.open_transaction_count,
        active_transaction.transaction_begin_time,
        DATEDIFF(SECOND, active_transaction.transaction_begin_time, SYSUTCDATETIME()) AS transaction_age_seconds,
        waiting_request.session_id AS waiting_session_id,
        waiting_session.login_name AS waiting_login,
        waiting_session.program_name AS waiting_program,
        DB_NAME(waiting_request.database_id) AS waiting_database,
        waiting_request.wait_type,
        waiting_request.wait_time AS wait_time_ms
    FROM sys.dm_exec_sessions AS transaction_holder
    INNER JOIN sys.dm_exec_requests AS waiting_request
        ON waiting_request.blocking_session_id = transaction_holder.session_id
    INNER JOIN sys.dm_exec_sessions AS waiting_session
        ON waiting_session.session_id = waiting_request.session_id
    INNER JOIN sys.dm_tran_session_transactions AS session_transaction
        ON session_transaction.session_id = transaction_holder.session_id
    INNER JOIN sys.dm_tran_active_transactions AS active_transaction
        ON active_transaction.transaction_id = session_transaction.transaction_id
    WHERE transaction_holder.is_user_process = 1
      AND DB_NAME(waiting_request.database_id) = N'CaldovaBenefits'
      AND waiting_request.wait_type LIKE N'LCK_M_%'
    ORDER BY waiting_request.wait_time DESC;
END;
GO

GRANT EXECUTE ON dbo.GetOperationsTransactionActivity TO [caldova_sre_reader];
GO
