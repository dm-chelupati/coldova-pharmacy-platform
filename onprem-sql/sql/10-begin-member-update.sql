USE [CaldovaBenefits];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION CaldovaBenefitsSchemaUpdate;

ALTER TABLE dbo.MemberBenefits
ADD OperationsReviewTag uniqueidentifier NULL;

RAISERROR(
    'The member benefits update transaction remains open for observation.',
    10,
    1
) WITH NOWAIT;

WAITFOR DELAY '23:59:59';

ROLLBACK TRANSACTION CaldovaBenefitsSchemaUpdate;
GO
