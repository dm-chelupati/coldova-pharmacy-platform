USE [CaldovaBenefits];
GO

SET NOCOUNT ON;

SELECT
    MemberId,
    IsEligible,
    PlanName,
    RxGroup,
    CopayAmount
FROM dbo.MemberBenefits WITH (READCOMMITTEDLOCK)
WHERE MemberId = 1001;
GO
