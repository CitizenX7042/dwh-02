# 05 – AI Data Sources (Quotation Assistant)

**Update:** Pricing engine reverse-engineered (`09_Pricing_Engine.md`); MainAccounts confirmed; lifecycle copy vs base clarified.

---

## 1. Highest-value sources (confirmed)

| Need | Source | Notes |
|------|--------|-------|
| Historical quotations | `Stock`/`StockMoves` **DocumentID=7** | 33.9k docs |
| Quote→downstream lineage | `BaseMoveID` chains + Doc 6/4/1 | via `AddBaseMoves` / `IssueDoc` |
| Copied quote lines without lineage | `InvCopy*` path | prices preserved; no BaseMoveID |
| Customer | `Accounts` **MainAccountID=1** (לקוחות) | BalanceCode often 6 |
| Supplier | `Accounts` **MainAccountID=2** (ספקים) | BalanceCode often 7 |
| Item catalog | `Items` | fallback price `Items.Price` |
| List prices | `PriceLists` + link via `Discounts.PriceListNumber` | date `DatF` |
| Matrix discounts | `Discounts` × `Items.DiscountCode` | also selects list |
| Special / qty breaks | `SpecialPrices` + `SpecialPricesMoves` | Active=0 means active |
| Deterministic engine | procs `GPRICE` + `Get*SPrice` | reproduce quote price |
| Historical net examples | Docs 4/1/2 + `GetAllDocPrices` logic | line×header disc compound |
| FX / VAT inputs | `Rates`, `Stock.VatPrc`, line `VatExampt` | VAT **after** GPRICE |

---

## 2. Pricing inputs the AI / rules layer must respect

To explain or reproduce a quote line price:

1. AccountKey (+ AssignKey / Dumi specials)  
2. ItemKey + DiscountCode  
3. Quantity  
4. As-of date (`DatF` / ValueDate)  
5. DocumentID (SalesDoc path)  
6. Matching Discounts / PriceLists / SpecialPrices rows  

See full precedence in `09_Pricing_Engine.md`.

---

## 3. AlterNum / AlterKeys (updated)

Master AlterKeys remains small (5 accounts / 483 items). **By document type**, alternate codes matter most on:

| Priority | Document | AlterNum % of lines |
|----------|----------|--------------------:|
| 1 | Doc **2** חשבונית מס/קבלה | **8.79%** |
| 2 | Doc 7 quotation | 0.12% |
| 3 | Doc 6 / 1 / 4 | ≤0.04% |

**AI implication:** Prefer Doc 2 (+ AlterKeys) for customer SKU language; do **not** expect AlterNum on quotations.

Quote conversion: BaseMoveID proves ≥~10% of quotes link into Doc 1; InvCopy conversions are invisible — see `15_Quotation_Conversion_Analysis.md`.

---

## 4. Risks

| Risk | Status |
|------|--------|
| Unknown quote ID | Resolved (7) |
| Wrong primary invoice | Resolved (1) |
| Price precedence unknown | **Resolved in 09** (engine mapped) |
| FatherPriceList / SonPriceList | **Not used** by any procedure in `generate_scripts.sql` (views only); GPRICE ignores them |
| Conversion copy vs reprice | Sales BaseDocs **copy**; GPRICE on convert only if PurchFlag=2; `RepriceDoc` is explicit |
| BaseMoveID undercounts conversions | **Confirmed** — InvCopy has no lineage |
| PII / PDFs | Unchanged |

---

## 5. Non-goals

No AI schema / embeddings / DWH mart in this phase.
