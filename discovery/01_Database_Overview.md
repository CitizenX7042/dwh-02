# 01 – Database Overview

**Scope:** Source-system discovery only. No DWH, AI schema, ETL, or BI design.  
**Update:** Refined with data-profile results from `query results/` (DocumentsDef, volumes, Accounts classification, Operations, AccItemsUpdateLog, AlterKeys, procedure/trigger inventories).

---

## 1. High-level inventory (unchanged facts)

| Object type | Count | Notes |
|-------------|------:|-------|
| Database | 1 | `DANOR13` |
| Tables | 783 | `dbo` |
| Views | 1,147 | `dbo` |
| Procedures | **263** | **FACT** from inventory |
| Triggers (table) | **30** | **FACT** — includes Stock, StockMoves, pricing, journal |
| Functions | **7** | Mostly utilities / loan math |
| Declared FKs | **0** | |
| Schemas `wizread`/`wizsoft` | empty of objects in script | |

**Product family (Assumption, High):** Softwise Hashavshevet-style ERP.

---

## 2. Architectural pattern (FACT)

- **`DocumentsDef`** = document-type dictionary (now fully profiled — see §4)
- **`Stock` / `StockMoves`** = polymorphic commercial document header/lines
- **`Accounts`** = customers + suppliers + GL cards in one table
- **`Items`** = item master
- **`JurnalTrans*`** = accounting journal
- Relationships are logical (shared keys), not FK-enforced
- **Triggers** on core tables likely feed **`Operations`** (Assumption pending trigger DDL)

---

## 3. Verified DocumentID dictionary (FACT)

Source: `documentsDef_table.xlsx` + business clarification that Doc **37** is חשבונית מרכזת (rarely primary).

| ID | DocName (Hebrew) | English gloss | SalesDoc | ForseenOrder | StockUpdate | UpdatFJurnal | StockInOut | Role family |
|---:|------------------|---------------|----------|--------------|-------------|--------------|------------|-------------|
| 1 | חשבונית מס | Tax invoice | 1 | 0 | -1 | 1 | 1 | **Sales invoice** |
| 2 | חשבונית מס/קבלה | Tax invoice + receipt | 1 | 0 | -1 | 1 | 1 | **Sales invoice/receipt** |
| 3 | חשבונית מס זיכוי | Credit tax invoice | 1 | 0 | 1 | -1 | 0 | **Sales credit** |
| 4 | תעודת משלוח | Delivery note | 1 | 0 | -1 | 0 | 1 | **Delivery** |
| 5 | החזרה | Return | 1 | 0 | 1 | 0 | 0 | **Sales return** |
| 6 | הזמנה | Sales order | 1 | -1 | 0 | 0 | 1 | **Sales order** |
| 7 | הצעת מחיר | Quotation | 1 | 0 | 0 | 0 | 1 | **Quotation** |
| 12 | חשבונית רכש | Purchase invoice | 0 | 0 | 1 | -1 | 0 | Purchase invoice |
| 13 | זיכוי רכש | Purchase credit | 0 | 0 | -1 | 1 | 1 | Purchase credit |
| 14 | ת.מ.רכש | Purchase delivery | 0 | 0 | 1 | 0 | 0 | Purchase receipt/DN |
| 15 | החזרה רכש | Purchase return | 0 | 0 | -1 | 0 | 1 | Purchase return |
| 16 | הצעת מחיר רכש | Purchase quotation | 0 | 0 | 0 | 0 | 0 | Purchase quote |
| 17 | הזמנת רכש | Purchase order | 0 | 1 | 0 | 0 | 0 | **Purchase order** |
| 31 | קבלה | Receipt | 0 | 0 | 0 | -1 | 0 | **Receipt** |
| 37 | חשבונית מס ריכוז | Concentration / summary invoice | 1 | 0 | -1 | 1 | 1 | Summary invoice (secondary) |
| 40–41, 33 | הפקדות | Bank deposits | 0 | 0 | 0 | -1 | 0 | Cashier deposits |
| 43 | העברה ישירה לבנק | Direct bank transfer | 0 | 0 | 0 | -1 | 0 | Bank transfer receipt-like |
| 76 | חיוב ספק | Supplier charge | 0 | 0 | -1 | 1 | 1 | Supplier charge |

Full dictionary with all ~140 types: see `02_Business_Process.md` and source Excel. Many types exist in config with **zero or near-zero Stock volume**.

**Flag interpretation (Evidence from active docs + Softwise norms):**

| Flag | Observed meaning |
|------|------------------|
| `SalesDoc = 1` | Sales-side document |
| `SalesDoc = 0` | Purchase / receipt / other |
| `ForseenOrder = -1` | Sales open-order family |
| `ForseenOrder = 1` | Purchase open-order family |
| `StockUpdate = -1` | Decreases inventory (sales out) |
| `StockUpdate = 1` | Increases inventory |
| `StockUpdate = 0` | No inventory effect (quotes, orders, receipts) |
| `UpdatFJurnal = 1` / `-1` / `0` | Posts / reverse-posts / no journal |

---

## 4. Actively used documents (FACT — volumes)

Source: `Document volumes and date ranges.xlsx`

| Rank | ID | Name | Count | First→Last ValueDate | Cancelled |
|-----:|---:|------|------:|----------------------|----------:|
| 1 | 1 | חשבונית מס | **131,974** | 2012→2026-07-17 | 4 |
| 2 | 2 | חשבונית מס/קבלה | **54,705** | 2012→2026-07-16 | 0 |
| 3 | 7 | הצעת מחיר | **33,902** | 2009→2026-07-16 | 0 |
| 4 | 31 | קבלה | **23,832** | 2012→2026-07-16 | 8 |
| 5 | 4 | תעודת משלוח | **20,855** | 2013→2026-07-16 | 0 |
| 6 | 43 | העברה ישירה לבנק | 17,164 | 2013→2026 | 3 |
| 7 | 6 | הזמנה | **16,022** | 2009→2026-07-16 | 0 |
| 8 | 3 | חשבונית מס זיכוי | 12,116 | 2012→2026 | 0 |
| 9 | 14 | ת.מ.רכש | 5,458 | 2021→2026 | 0 |
| 10 | 12 | חשבונית רכש | 5,414 | 2015→2026 | 0 |
| … | 37 | חשבונית מס ריכוז | **2,865** | 2013→2026-06-30 | 0 |
| … | 5 | החזרה | 1,824 | 2013→2026 | 0 |
| … | 17 | הזמנת רכש | 169 | 2022→2026 | 0 |

**Corrections to prior discovery**

- **Primary sales invoice = DocumentID 1** (not 37).
- **Primary delivery = DocumentID 4**.
- **Quotations are real and heavy: DocumentID 7** (33.9k) — previously “unproven”.
- DocumentID **37** = summary/concentration invoice; used, but far less than 1 and 4. **Business confirmation:** hardly used relative to חשבונית + תעודת משלוח.

---

## 5. Accounts classification (refined)

**FACT:** 4,369 accounts; 346 distinct (`Filter`,`BalanceCode`,`MainAccount`,`WorF`) combos.

| Signal | Role | Confidence |
|--------|------|------------|
| **`MainAccount = 1`** | **לקוחות (Customers)** | **High** — `MainAccounts.xlsx` |
| **`MainAccount = 2`** | **ספקים (Suppliers)** | **High** — `MainAccounts.xlsx` |
| **`BalanceCode = 6`** | לקוחות | **High** — `BalanceCodes.xlsx` |
| **`BalanceCode = 7`** | ספקים | **High** — `BalanceCodes.xlsx` |
| **`Filter`** (`משרד^`, `מוסד^`, …) | Customer **segment** | **High** |
| **`WorF`** on suppliers | Merchandise category | **Medium–High** |
| Other MainAccounts (3=expenses, 4=banks, 7=VAT-liable income, 26=none, 30=blocked, …) | GL classes | **High** names; usage varies |

**Filter is not** the cust/supplier discriminator.

---

## 6. Most important tables (updated)

| Priority | Table | Why |
|----------|-------|-----|
| Critical | `Stock` / `StockMoves` | All commercial docs incl. quotes |
| Critical | `DocumentsDef` | Verified type dictionary |
| Critical | `Accounts` / `Items` | Masters |
| Critical | `JurnalTrans*` | GL |
| High | `PriceLists*`, `SpecialPrices*`, `Discounts` | Pricing for quotes |
| High | Doc 7 history in Stock* | Quotation corpus for AI |
| High | `Operations` + **triggers** | Candidate CDC (see 06) |
| High | `AccItemsUpdateLog` | Master field-change log (active) |
| Medium | `AlterKeys` | Useful but narrow (5 accounts) |

---

## 7. Physical size highlights (unchanged CSV)

`InvPdfFiles` ~6 GB; `StockMoves` 1.6M rows; `Stock` 338k; `Operations` 5.1M; journal large.

---

## 8. Runtime logic inventory (new)

| Kind | Count | Implication |
|------|------:|-------------|
| Procedures | 263 | Selectively review — see `08_Required_Runtime_Logic.md` |
| Triggers on Stock/StockMoves/pricing/journal | Yes | Likely source of Operations events |
| Price engine proc | `GPRICE` (+ helpers) | Priority for quotation pricing rules |

---

## 9. Bottom line

This is an active Softwise ERP for an office-supplies style distributor (segment filters + supplier WorF categories). Core sales path is:

**הצעת מחיר (7) → הזמנה (6) → תעודת משלוח (4) → חשבונית מס (1)**  
with heavy **חשבונית מס/קבלה (2)** and **קבלה (31)**.

Quotations are first-class operational data — not hypothetical.
