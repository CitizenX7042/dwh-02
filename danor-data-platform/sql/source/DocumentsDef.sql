-- Read-only source extract for dbo.DocumentsDef
-- Columns verified from generate_scripts_tables_schema_view.sql
SELECT
    DocumentID,
    DocName,
    SalesDoc,
    ForseenOrder,
    StockUpdate,
    UpdatFJurnal,
    StockInOut
FROM dbo.DocumentsDef
