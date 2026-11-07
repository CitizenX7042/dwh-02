/*
  Azure SQL — staging tables for the first reference PoC.

  Type notes (review):
  - Source Softwise uses varchar for many Hebrew text columns.
  - Staging uses nvarchar for Unicode-safe ODBC transfer of Hebrew.
  - Source IDENTITY columns are stored as plain int (no target IDENTITY).
  - float mirrors source float columns used by Softwise pricing.
*/

IF OBJECT_ID(N'stage.DocumentsDef', N'U') IS NULL
BEGIN
    CREATE TABLE stage.DocumentsDef
    (
        DocumentID      int             NOT NULL,
        DocName         nvarchar(50)    NULL,
        SalesDoc        tinyint         NULL,
        ForseenOrder    smallint        NULL,
        StockUpdate     smallint        NULL,
        UpdatFJurnal    smallint        NULL,
        StockInOut      tinyint         NULL,
        SourceSystem    nvarchar(64)    NOT NULL,
        ExtractedAtUtc  datetime2(3)    NOT NULL,
        EtlRunId        uniqueidentifier NOT NULL,
        CONSTRAINT PK_stage_DocumentsDef PRIMARY KEY CLUSTERED (DocumentID)
    );
END
GO

IF OBJECT_ID(N'stage.Items', N'U') IS NULL
BEGIN
    CREATE TABLE stage.Items
    (
        ID              int             NOT NULL,
        ItemKey         nvarchar(20)    NULL,
        ItemName        nvarchar(100)   NULL,
        ForignName      nvarchar(100)   NULL,
        BarCode         nvarchar(20)    NULL,
        Price           float           NULL,
        PurchPrice      float           NULL,
        Currency        nvarchar(5)     NULL,
        DiscountCode    nvarchar(5)     NULL,
        SortGroup       int             NULL,
        Quantity        float           NULL,
        Dumi            tinyint         NULL,
        SourceSystem    nvarchar(64)    NOT NULL,
        ExtractedAtUtc  datetime2(3)    NOT NULL,
        EtlRunId        uniqueidentifier NOT NULL,
        CONSTRAINT PK_stage_Items PRIMARY KEY CLUSTERED (ID)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_stage_Items_ItemKey'
      AND object_id = OBJECT_ID(N'stage.Items')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_stage_Items_ItemKey ON stage.Items (ItemKey);
END
GO

IF OBJECT_ID(N'stage.Accounts', N'U') IS NULL
BEGIN
    CREATE TABLE stage.Accounts
    (
        ID               int             NOT NULL,
        AccountKey       nvarchar(15)    NULL,
        FullName         nvarchar(50)    NULL,
        MainAccount      int             NULL,
        BalanceCode      int             NULL,
        Filter           nvarchar(5)     NULL,
        Agent            int             NULL,
        CreditTermsCode  int             NULL,
        DiscountCode     int             NULL,
        DocCurr          nvarchar(5)     NULL,
        AssignKey        nvarchar(15)    NULL,
        SourceSystem     nvarchar(64)    NOT NULL,
        ExtractedAtUtc   datetime2(3)    NOT NULL,
        EtlRunId         uniqueidentifier NOT NULL,
        CONSTRAINT PK_stage_Accounts PRIMARY KEY CLUSTERED (ID)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_stage_Accounts_AccountKey'
      AND object_id = OBJECT_ID(N'stage.Accounts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_stage_Accounts_AccountKey ON stage.Accounts (AccountKey);
END
GO
