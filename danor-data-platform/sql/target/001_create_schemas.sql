/*
  Azure SQL — create schemas for staging and audit.
  Run once against the target database with a privileged deployment login.
  The ETL runtime login needs INSERT/UPDATE/DELETE/CREATE TABLE/DROP TABLE
  on stage (for work tables) and INSERT/UPDATE on audit.EtlRun.
*/
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'stage')
BEGIN
    EXEC(N'CREATE SCHEMA stage');
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'audit')
BEGIN
    EXEC(N'CREATE SCHEMA audit');
END
GO
