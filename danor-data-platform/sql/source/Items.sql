-- Read-only source extract for dbo.Items
-- Columns verified from generate_scripts_tables_schema_view.sql
-- Note: source spelling ForignName is intentional.
SELECT
    ID,
    ItemKey,
    ItemName,
    ForignName,
    BarCode,
    Price,
    PurchPrice,
    Currency,
    DiscountCode,
    SortGroup,
    Quantity,
    Dumi
FROM dbo.Items
