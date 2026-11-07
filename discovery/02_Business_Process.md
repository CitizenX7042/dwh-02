# 02 – Business Process Discovery

**Update:** Process map corrected using DocumentsDef + Stock volumes + business note on Doc 37.

---

## 1. Company nature (refined)

**Evidence**

- High volume of sales invoices (Doc 1), invoice/receipts (Doc 2), deliveries (Doc 4), quotations (Doc 7), orders (Doc 6).
- Account `Filter` segments: office (`משרד`), institutions, stores, schools, factories, hi-tech, Elbit — **B2B office/school supplies distribution**.
- Supplier cards carry merchandise WorF labels (writing instruments, paper, etc.).
- Purchase side active (Docs 12, 14) but smaller than sales.
- Manufacturing / warehouse-transfer DocumentIDs exist in config with **no meaningful Stock volume**.

**Assumption (High):** Wholesale/distribution of office and institutional supplies; not manufacturing-led.

---

## 2. Confirmed sales flow (FACT)

```
Customer (Accounts, MainAccount≈1)
        │
        ▼
הצעת מחיר          DocumentID = 7     (33,902 docs, active through 2026-07-16)
        │
        ▼
הזמנה              DocumentID = 6     (16,022)
        │
        ▼
תעודת משלוח        DocumentID = 4     (20,855)   StockUpdate=-1 (inventory out)
        │
        ▼
חשבונית מס         DocumentID = 1     (131,974)  primary invoice
   and/or
חשבונית מס/קבלה    DocumentID = 2     (54,705)   invoice+receipt combo
   and/or (less common)
חשבונית מס ריכוז   DocumentID = 37    (2,865)    summary invoice — secondary
        │
        ▼
קבלה / bank xfer   DocumentID = 31 / 43 / deposits 40,41,33
        │
        ▼
Journal + bank match
```

**Credits / returns**

| ID | Name | Count | Role |
|---:|------|------:|------|
| 3 | חשבונית מס זיכוי | 12,116 | Sales credit note |
| 5 | החזרה | 1,824 | Goods return |

**Document chaining mechanism (unchanged Evidence):** `StockMoves.BaseMoveID`, `BaseQuantity`/`SupplyQuantity`, `BaseDocs` config, procs `AddBaseMoves` / `InvCopy*`.

---

## 3. Purchase flow (FACT — smaller)

```
Supplier (Accounts, MainAccount≈2)
   → הזמנת רכש (17)           169 docs
   → ת.מ.רכש (14)             5,458
   → חשבונית רכש (12)         5,414
   → זיכוי/החזרה רכש (13/15)  hundreds
```

Purchase quotations (16) nearly unused (5 docs).

---

## 4. Quotation process — now confirmed

| Item | Status |
|------|--------|
| Quotation DocumentID | **7 – הצעת מחיר** |
| Volume | **33,902** — 3rd largest document type |
| Date span | 2009 → 2026-07-16 |
| StockUpdate | 0 (no inventory) |
| UpdatFJurnal | 0 (no journal) |
| SalesDoc | 1 |

Other quote-like types in dictionary (mostly unused): 16 purchase quote, 93 potential accounts, 94/106/108 export/service/rental quotes.

**AI implication:** Historical quotations in `Stock`/`StockMoves` where `DocumentID=7` are a primary training/retrieval corpus.

---

## 5. What DocumentID 37 actually is

| Prior discovery | Correction |
|-----------------|------------|
| Custom views labeled Doc 37 as “INVOICE” | **FACT name:** חשבונית מס ריכוז (concentration/summary invoice) |
| Treated as primary invoice candidate | **Business + volumes:** secondary; primary invoices are **1** (and **2**) |
| | Deliveries (**4**) + invoices (**1**) are the main operational pair |

---

## 6. Receipts & cash cycle

| ID | Name | Count |
|---:|------|------:|
| 31 | קבלה | 23,832 |
| 43 | העברה ישירה לבנק | 17,164 |
| 41 | הפקדה - אשראי | 4,032 |
| 40 | הפקדה - שקים | 3,857 |
| 33 | הפקדה - מזומן | 2,672 |

Payment instruments remain `CashPays` / `Cheqs` / `CreditPays` on receipt Stock rows; matching via `ReceiptJurnalMatch`.

---

## 7. Modules present but inactive / negligible (by Stock volume)

| Area | Example DocumentIDs | Evidence |
|------|---------------------|----------|
| Manufacturing | 20–23, 101–105 | No volume rows in profile |
| Warehouse transfer | 18, 19, 55, 56 | No volume |
| Agent docs | 9–11, 32, 87 | ≤4 docs |
| Export/import | 35, 36, 38, 100… | ≤1 meaningful |
| POS slips | 121–125 | 1 doc (מכירה בהקפה) |
| Service/rental | 79–118 | No volume in extract |

**Assumption:** Licensed Softwise modules exist in `DocumentsDef` but this company runs a classic sell-from-stock + quote/order/delivery/invoice cycle.

---

## 8. Status / cancel (refined with lifecycle procs)

| Mechanism | Behavior | Evidence |
|-----------|----------|----------|
| Draft vs issued | `Status=0` draft lines; `Status=1` issued/open bases | `IssueDoc`, `AddBaseMoves` |
| Conversion | `AddBaseMoves` sets `BaseMoveID`; reduces open `BaseQuantity`/`SupplyQuantity` on issue | lifecycle analysis |
| Copy conversion | `InvCopy*` copies prices/AlterNum; does not set `BaseMoveID` | `InvCopyAllLines` |
| Hard delete | `IDelDoc` deletes Stock+Moves | proc body |
| Soft `DocCancel` | Rare (Doc1: 4; Doc31: 8; sales 2–7/37: 0); written by `KB_Cancellation` | usage + proc |
| Receipt cancel | `KB_Cancellation` creates offsetting docs **and** sets DocCancel on source | proc |
| MoveCancel | Column exists; no SQL writers found | `generate_scripts.sql` |

See `10_Document_Lifecycle.md`, `14_Document_Status_And_Cancellation.md`.

---

## 9. Party classes (confirmed)

| MainAccountID | Description |
|--------------:|-------------|
| 1 | לקוחות (Customers) |
| 2 | ספקים (Suppliers) |
| 3+ | Expenses, banks, VAT, income, blocked, … |

| BalanceCode | Description |
|------------:|-------------|
| 6 | לקוחות |
| 7 | ספקים |

**FACT:** Matches prior inference from classification profile.

---

## 10. Process narrative (business language)

Danor issues many **quotations**, converts via **copy and/or BaseMoveID linking** into **orders**, **deliveries**, and often **directly into tax invoices** (Doc 1 is the largest BaseMoveID target from quotes). Pricing is deterministic (`GPRICE`); sales conversion normally **copies** quote prices. Soft cancel is negligible; receipts use KB offsets; drafts can be hard-deleted with `IDelDoc`. Details: `13_BaseDocs_Conversion_Matrix.md`, `15_Quotation_Conversion_Analysis.md`.
