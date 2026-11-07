# Danor ETL — Portable PoC (DANOR13 → Azure SQL staging)

Preparation-only Python ETL for Softwise **DANOR13** (read-only) into **Azure SQL Database** staging tables.

This repository is built on a laptop for later execution on an **approved company-managed network computer**. It does **not** assume Cursor has database connectivity.

## Scope (first PoC)

| Direction | Objects |
|-----------|---------|
| Source (read-only) | `dbo.DocumentsDef`, `dbo.Items`, `dbo.Accounts` |
| Target (write) | `stage.DocumentsDef`, `stage.Items`, `stage.Accounts`, `audit.EtlRun` |

- Full replacement into staging via work tables
- Manual CLI execution only
- No incremental load, scheduling, DWH facts/dims, Power BI, or AI objects
- **Production SQL Server is never modified** by this project

See also [ASSUMPTIONS.md](ASSUMPTIONS.md).

---

## 1. Required software (ETL computer)

On the approved Windows runner:

1. **Python 3.12** (64-bit recommended)
2. **Microsoft ODBC Driver 18 for SQL Server**
3. **Git** (if approved for cloning)
4. Network access to:
   - internal production SQL Server (DANOR13)
   - Azure SQL Database (outbound TLS)

---

## 2. Verify Python and ODBC

```powershell
python --version
# Expect: Python 3.12.x

Get-OdbcDriver | Where-Object { $_.Name -like "*ODBC Driver 18*" }
# Expect a row: ODBC Driver 18 for SQL Server
```

If `python` is not found, use the Python 3.12 installer and ensure Add to PATH is enabled, or call `py -3.12`.

---

## 3. Create a virtual environment

From the project root (`danor-data-platform`):

```powershell
cd <path-to>\danor-data-platform
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
```

---

## 4. Install the project

```powershell
pip install -e ".[dev]"
```

Optional unit tests (no database):

```powershell
pytest -q
```

---

## 5. Copy environment template

```powershell
Copy-Item .env.example .env
```

`.env` is gitignored. **Never commit it.**

---

## 6. Populate `.env` locally (do not expose credentials)

Edit `.env` on the ETL computer only. Put hostnames, ports, and passwords only in that local file.

| Variable | Guidance |
|----------|----------|
| `SOURCE_SQL_SERVER` | Production SQL host or listener (not localhost unless that machine hosts SQL) |
| `SOURCE_SQL_PORT` | Blank for default instance, or TCP port |
| `SOURCE_SQL_DATABASE` | Must be `DANOR13` |
| `SOURCE_SQL_USERNAME` | `danor_etl_reader` |
| `SOURCE_SQL_PASSWORD` | Out-of-band secret; never paste into chat |
| `SOURCE_SQL_ENCRYPT` | Per company policy (`yes` / `no`) |
| `SOURCE_SQL_TRUST_SERVER_CERTIFICATE` | Per company policy |
| `TARGET_SQL_SERVER` | Azure SQL FQDN (`*.database.windows.net`) |
| `TARGET_SQL_DATABASE` | Azure database name |
| `TARGET_SQL_USERNAME` / `PASSWORD` | Azure login with stage/audit rights |
| `TARGET_SQL_ENCRYPT` | `yes` |
| `TARGET_SQL_TRUST_SERVER_CERTIFICATE` | `no` |

The application never prints passwords or full connection strings.

---

## 7. Find SQL Server hostname and port

Ask the DBA / Softwise admin for the SQL host or Always On listener, instance/port, and confirmation that `danor_etl_reader` is mapped to DANOR13 as read-only. Do not hardcode hosts in code.

---

## 8. Test network connectivity

```powershell
Test-NetConnection -ComputerName <SOURCE_HOST> -Port 1433
Test-NetConnection -ComputerName <azure>.database.windows.net -Port 1433
```

---

## 9. Run Azure SQL setup scripts

Against **Azure SQL only** (deployment login), in order:

1. `sql/target/001_create_schemas.sql`
2. `sql/target/002_create_audit_tables.sql`
3. `sql/target/003_create_stage_tables.sql`

Grant the ETL login: DML + TRUNCATE on `stage.*`, CREATE/DROP TABLE on `stage` (work tables), INSERT/UPDATE on `audit.EtlRun`.

Never run these scripts against DANOR13.

---

## 10. Run commands

Activate the venv first.

```powershell
python -m danor_etl.cli test-source
python -m danor_etl.cli test-target

python -m danor_etl.cli load-table DocumentsDef --max-rows 100 --dry-run --source-only
python -m danor_etl.cli load-table DocumentsDef --max-rows 100 --dry-run

python -m danor_etl.cli load-table DocumentsDef --max-rows 100
python -m danor_etl.cli load-table Items --max-rows 100
python -m danor_etl.cli load-table Accounts --max-rows 100

python -m danor_etl.cli load-reference
```

---

## 11. Validate row counts

Source:

```sql
SELECT COUNT(*) FROM dbo.DocumentsDef;
SELECT COUNT(*) FROM dbo.Items;
SELECT COUNT(*) FROM dbo.Accounts;
```

Azure:

```sql
SELECT COUNT(*) FROM stage.DocumentsDef;
SELECT COUNT(*) FROM stage.Items;
SELECT COUNT(*) FROM stage.Accounts;
SELECT TOP 20 * FROM audit.EtlRun ORDER BY StartTimeUtc DESC;
```

Full loads without `--max-rows` should match source counts. With `--max-rows`, stage contains only the sample (full replace of stage content).

---

## 12. Verify Hebrew text

```sql
SELECT TOP 20 DocumentID, DocName FROM stage.DocumentsDef ORDER BY DocumentID;
SELECT TOP 20 ItemKey, ItemName, ForignName FROM stage.Items WHERE ItemName IS NOT NULL;
SELECT TOP 20 AccountKey, FullName FROM stage.Accounts WHERE FullName IS NOT NULL;
```

Confirm Hebrew renders correctly (not `???`).

---

## 13. Move to another ETL computer

1. Install same Python 3.12 and ODBC Driver 18  
2. Copy/clone repo without `.env`  
3. Recreate venv and `pip install -e ".[dev]"`  
4. New local `.env` from `.env.example`  
5. Update firewall for the new runner  
6. Run `test-source`, `test-target`, then `--max-rows 100` load  

No code changes required.

---

## 14. Production SQL Server must never be modified

- Source login is read-only  
- Validator allows only SELECT / WITH…SELECT  
- No EXEC, DML, DDL, or multi-statement batches against source  
- Writes only on Azure SQL  

Permissions remain the primary control; the validator is an extra guard.

---

## Load safety pattern

1. Extract in chunks (`fetchmany`)  
2. Load `stage._etl_work_<Table>_<RunId>`  
3. Validate counts  
4. Transaction: truncate final stage + insert from work  
5. Drop work table  
6. Write `audit.EtlRun`  

On failure, previous stage data remains. File lock under `ETL_LOCK_DIR` prevents concurrent runs on the same machine.

---

## Project layout

```text
danor-data-platform/
  pyproject.toml
  .env.example
  config/tables.yaml
  sql/source/*.sql
  sql/target/*.sql
  src/danor_etl/
  tests/
  README.md
  ASSUMPTIONS.md
```
