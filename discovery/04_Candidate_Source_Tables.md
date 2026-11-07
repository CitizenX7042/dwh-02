# 04 – Candidate Source Tables

**Update:** Document candidates now use verified DocumentIDs and volumes. AlterKeys quantified.

---

## Items — `Items` — **High**

Unchanged. ~9.8k items. AccItemsUpdateLog proves live edits to name, barcode, sale price, active flag.

---

## Customers — `Accounts` where MainAccount≈1 — **High**

**Evidence:** volume of MA=1 (~2925); sales documents; segment Filters.  
**BalanceCode** often 6.  
Still validate with `MainAccounts` descriptions.

---

## Suppliers — `Accounts` where MainAccount≈2 — **High**

**Evidence:** MA=2 (~750), BC often 7; AccItemsUpdateLog supplier create; purchase docs 12/14.

---

## Inventory

Unchanged candidates: `Items.Quantity`, inventory-affecting `StockMoves` (Docs with StockUpdate≠0, esp. 4,1,5,14,12), `AgentWarehouseNames`.  
Transfers/manufacturing docs unused.

---

## Price Lists — `PriceListNames` + `PriceLists` — **High**

Ops show PriceLists Insert/Delete activity. Triggers present.

---

## Customer Prices — `SpecialPrices*` + `Discounts` — **High**

Unchanged. Engine entry points: `GPRICE`, `Get*SPrice`.

---

## Orders — `Stock` DocumentID **6** — **High**

16,022 docs, active. Agent order Doc 11 negligible (2).

---

## Order Lines — `StockMoves` for DocumentID **6** — **High**

---

## Invoices — **corrected**

| Candidate | Confidence | Notes |
|-----------|------------|-------|
| **`Stock` DocumentID = 1** (חשבונית מס) | **High** | **Primary** — 131,974 docs |
| **`Stock` DocumentID = 2** (חשבונית מס/קבלה) | **High** | 54,705 — invoice+receipt |
| `Stock` DocumentID = 37 (חשבונית מס ריכוז) | **Medium** | 2,865 — summary; **not** primary |

Prior Medium–High on Doc 37 as “the invoice” is **withdrawn**.

---

## Invoice Lines — `StockMoves` for Docs **1 / 2** (and 37 if needed) — **High**

---

## Quotations — **corrected from Low–Medium → High**

| Candidate | Confidence | Notes |
|-----------|------------|-------|
| **`Stock` DocumentID = 7** (הצעת מחיר) | **High** | 33,902 docs since 2009 |
| Lines: `StockMoves` where DocumentID=7 | **High** | |

---

## Quotation Lines — `StockMoves` DocumentID **7** — **High**

---

## Deliveries — **new explicit candidate**

| Candidate | Confidence |
|-----------|------------|
| `Stock` / `StockMoves` DocumentID **4** | **High** (20,855) |

---

## Transactions (GL) — `JurnalTrans*` — **High**

Unchanged.

---

## Payments — receipt Docs **31/43/40/41/33** + CashPays/Cheqs/CreditPays — **High**

---

## Returns / credits

| Candidate | Confidence |
|-----------|------------|
| Doc **3** credit invoice | **High** |
| Doc **5** return | **High** |
| `KupReturns` | **Low** for this company (POS unused) |

---

## Manufacturers — **None** — unchanged

---

## Categories — `ItemSortNames` / `AccSortNames` / `Filter` segments — **High**

Filter is customer segment taxonomy.

---

## UoM / Currencies / Tax / Discounts / Salesperson — largely unchanged

---

## Document Status — `Stock.Status` + `StatLog` + cancel flags — **High**

Cancel rare on top documents.

---

## Modification Tracking — refined

| Source | Assessment |
|--------|------------|
| `AccItemsUpdateLog` | **High** for Items/Accounts field changes (active Jul 2026) |
| `Operations` + triggers | **Medium** for inserts/deletes of Stock/Moves/Journal/Prices; **weak for updates** |
| No ModifiedDate/RowVersion on Stock* | unchanged |

---

## AlterKeys / alternate codes — quantified

| Metric | Value | Interpretation |
|--------|------:|----------------|
| AlterKeys rows | 1,376 | Small master |
| Distinct accounts with aliases | **5** | Narrow customer coverage |
| Distinct items with aliases | 483 | Meaningful item coverage for those accounts |
| StockMoves lines with AlterNum | 11,792 / 1,608,237 (**0.73%**) | Rare on historical lines overall |

**Confidence as AI source:** **Medium** — high value for the few aliased customers; not a global alias system.

---

## Quick matrix (updated)

| Concept | Primary candidate | Confidence |
|---------|-------------------|------------|
| Quotations | Stock/Moves **Doc 7** | High |
| Sales orders | Stock/Moves **Doc 6** | High |
| Deliveries | Stock/Moves **Doc 4** | High |
| Invoices | Stock/Moves **Doc 1** (then 2) | High |
| Summary invoice | Doc **37** | Medium (secondary) |
| Credits | Doc **3** | High |
| Returns | Doc **5** | High |
| Receipts | Doc **31** (+43/deposits) | High |
| Purchase orders | Doc **17** | Medium (low volume) |
| Customers | Accounts MA≈1 | High |
| Suppliers | Accounts MA≈2 | High |
| AlterKeys | AlterKeys | Medium (5 accounts) |
