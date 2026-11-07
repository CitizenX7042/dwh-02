# Assumptions and verification notes

First portable ETL PoC. Source columns verified against  
`C:\Danyor_project\sql server\generate_scripts_tables_schema_view.sql`.

---

## 1. Source columns — verification status

### DocumentsDef (all verified)

| Column | Source type | Notes |
|--------|-------------|-------|
| DocumentID | int IDENTITY | Stored on target as int (no IDENTITY) |
| DocName | varchar(50) | Hebrew labels |
| SalesDoc | tinyint | |
| ForseenOrder | smallint | Source spelling `ForseenOrder` |
| StockUpdate | smallint | |
| UpdatFJurnal | smallint | |
| StockInOut | tinyint | |

No requested DocumentsDef column was unverifiable.

Optional flags considered but **excluded** from PoC (exist on source; not required for first classification load):  
`FixNumerator`, `ExportDoc`, `BaseLinesOnly`, `HsDoc`, `ProductDoc`, etc.

### Items (all verified)

| Column | Source type | Notes |
|--------|-------------|-------|
| ID | int IDENTITY | Target int, no IDENTITY |
| ItemKey | varchar(20) | Business key |
| ItemName | varchar(100) | |
| ForignName | varchar(100) | Source spelling retained |
| BarCode | varchar(20) | |
| Price | float | |
| PurchPrice | float | |
| Currency | varchar(5) | |
| DiscountCode | varchar(5) | **Not int** on Items |
| SortGroup | int | |
| Quantity | float | |
| Dumi | tinyint | |

No requested Items column was unverifiable.

### Accounts (all verified)

| Column | Source type | Notes |
|--------|-------------|-------|
| ID | int IDENTITY | Target int, no IDENTITY |
| AccountKey | varchar(15) | Business key |
| FullName | varchar(50) | |
| MainAccount | int | |
| BalanceCode | int | |
| Filter | varchar(5) | Segment, not cust/supplier |
| Agent | int | |
| CreditTermsCode | int | |
| DiscountCode | int | **int** on Accounts (differs from Items) |
| DocCurr | varchar(5) | |
| AssignKey | varchar(15) | |

No requested Accounts column was unverifiable.

### Intentionally excluded (PII / unnecessary)

Address, City, Phone, Fax, EMail, Details, CustomerNote, WebSite, bank/card fields (`Sb*`), TaxFileNum, etc.

---

## 2. Source columns that could not be verified

**None** for the PoC column lists above — all names and types were found in the schema script.

---

## 3. Target data-type decisions requiring review

| Decision | Choice | Review needed? |
|----------|--------|----------------|
| Hebrew / text columns | `nvarchar` on Azure (source is `varchar`) | **Yes** — confirm Unicode round-trip; alternative is keep `varchar` + collation |
| Money-like amounts | `float` (matches Softwise source) | **Yes** — later DWH may prefer `decimal` |
| Source IDENTITY | Plain `int` on stage | No (by design) |
| DocumentsDef PK | `DocumentID` | No |
| Items PK | `ID` (+ index on `ItemKey`) | Optional: natural key uniqueness |
| Accounts PK | `ID` (+ index on `AccountKey`) | Optional: natural key uniqueness |
| Metadata | `SourceSystem`, `ExtractedAtUtc`, `EtlRunId` | No |

---

## 4. Runtime assumptions

1. ODBC Driver 18 is installed on the ETL runner.  
2. `danor_etl_reader` remains read-only on DANOR13.  
3. Azure ETL login may create/drop tables in schema `stage` for work tables.  
4. File lock is per-machine only (not distributed).  
5. `--max-rows` uses `SELECT TOP (n)` and **replaces** the entire stage table with the sample.  
6. Source Softwise `varchar` Hebrew is transferred via ODBC into `nvarchar` staging.  
7. Hostname is logged for audit only; behavior does not depend on it.

---

## 5. Out of scope (confirmed)

- Incremental CDC / Operations-based loads  
- Scheduling  
- DWH star schema  
- AI / embedding objects  
- Stored procedure execution against source  
