/*
  Azure SQL — ETL run audit table.
*/
IF OBJECT_ID(N'audit.EtlRun', N'U') IS NULL
BEGIN
    CREATE TABLE audit.EtlRun
    (
        RunId               uniqueidentifier NOT NULL,
        ParentRunId         uniqueidentifier NULL,
        TableName           nvarchar(128)    NOT NULL,
        LoadMode            nvarchar(32)     NOT NULL,
        StartTimeUtc        datetime2(3)     NOT NULL,
        EndTimeUtc          datetime2(3)     NULL,
        SourceRowCount      bigint           NULL,
        WorkTableRowCount   bigint           NULL,
        TargetRowCount      bigint           NULL,
        Status              nvarchar(32)     NOT NULL,
        ErrorMessage        nvarchar(max)    NULL,
        RunnerHost          nvarchar(128)    NOT NULL,
        SourceSystem        nvarchar(64)     NOT NULL,
        CreatedAtUtc        datetime2(3)     NOT NULL
            CONSTRAINT DF_EtlRun_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_EtlRun PRIMARY KEY CLUSTERED (RunId)
    );
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_EtlRun_TableName_StartTimeUtc'
      AND object_id = OBJECT_ID(N'audit.EtlRun')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_EtlRun_TableName_StartTimeUtc
        ON audit.EtlRun (TableName, StartTimeUtc DESC);
END
GO
