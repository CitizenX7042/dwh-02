-- Read-only source extract for dbo.Accounts
-- Columns verified from generate_scripts_tables_schema_view.sql
-- PII contact fields intentionally excluded (Address, Phone, EMail, etc.).
SELECT
    ID,
    AccountKey,
    FullName,
    MainAccount,
    BalanceCode,
    Filter,
    Agent,
    CreditTermsCode,
    DiscountCode,
    DocCurr,
    AssignKey
FROM dbo.Accounts
