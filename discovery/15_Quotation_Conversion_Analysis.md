# 15 – Quotation Conversion Analysis

**Purpose:** Measure how quotations (DocumentID=7) convert downstream using BaseMoveID lineage, and bound what the metric cannot see.  
**Sources:** Quote lineage Excel, document volumes, BaseDocs matrix (`13`), `AddBaseMoves` / `InvCopy*` behavior (`10`).

---

## 1. Totals

| Metric | Value | Notes |
|--------|------:|-------|
| Total quotations (Stock Doc 7) | **33,902** | Document volumes profile |
| Soft-cancelled Doc 7 | **0** | User soft-cancel counts |

---

## 2. Proven BaseMoveID lineage (child docs referencing quote lines)

Child documents whose lines point (`BaseMoveID`) to StockMoves belonging to DocumentID=7:

| Child DocumentID | Name | QuotesReferenced | LinkedChildLines |
|-----------------:|------|-----------------:|-----------------:|
| 1 | חשבונית מס | 3,280 | 34,128 |
| 6 | הזמנה | 2,167 | 19,822 |
| 7 | הצעת מחיר | 704 | 13,778 |
| 4 | תעודת משלוח | 459 | 3,515 |
| 2 | חשבונית מס/קבלה | 70 | 508 |
| 37 | חשבונית מס ריכוז | 5 | 66 |

### Conversion percentage (BaseMoveID-visible)

**Caveat:** `QuotesReferenced` counts are **per child type** and **can overlap** (same quote can feed an order and later an invoice). Without a unique-quote distinct query, exact unique conversion rate is unknown.

| Bound | Calculation | Result |
|-------|-------------|-------:|
| Naive sum of QuotesReferenced | 3280+2167+704+459+70+5 | 6,685 path-hits (not unique quotes) |
| Lower bound on unique converted quotes | max(QuotesReferenced) across types = Doc1 | ≥ **3,280** (~**9.7%** of 33,902) |
| Upper bound (if zero overlap) | sum path-hits | ≤ **6,685** (~**19.7%**) — **optimistic / likely high** |
| Quote→quote BaseMoveID | 704 | Same-type chaining / split |

**Practical statement:** At least ~10% of quotations have **proven** BaseMoveID conversion into a tax invoice; order path shows ~6.4% (2167/33902); delivery path ~1.4%. Many quotes may convert only via **InvCopy** (invisible here) or remain unconverted.

---

## 3. Downstream type classification (BaseMoveID)

| Class | Types | Evidence |
|-------|-------|----------|
| Primary invoice target | Doc **1** | Highest quote references |
| Order intermediate | Doc **6** | Second |
| Same-type quote chain | Doc **7** | Configured 7→7 CancelBaseQnt=1 |
| Delivery | Doc **4** | Smaller |
| Invoice/receipt | Doc **2** | Rare from quotes |
| Summary invoice | Doc **37** | Negligible (5 quotes) |

Configured BaseDocs also allow direct 7→1/2/4/6/37 (see `13`). Lineage confirms **direct quote→invoice** is used in production, not only 7→6→4→1.

---

## 4. InvCopy conversions are invisible here

**FACT:** `InvCopyAllLines` / `InvCopyLine` copy Price/AlterNum/etc. but **do not set `BaseMoveID`**.

Therefore:

- A quotation converted only by copy into an order/invoice **will not appear** in the lineage query.
- Missing BaseMoveID lineage is **not proof of no conversion**.
- AI / analytics that need conversion rates must either:
  - combine BaseMoveID + heuristics (same account/date/items), or
  - capture UI path flags if available, or
  - accept undercount.

---

## 5. Alternate item codes on quotations

From `AlterNum.xlsx` (lines with AlterNum):

| DocumentID | AlterNum % of lines |
|-----------:|--------------------:|
| 2 invoice/receipt | **8.79%** |
| 7 quotation | **0.12%** |
| 6 order | 0.04% |
| 1 invoice | 0.03% |
| 4 delivery | 0.01% |

**Verdict for AI:** Alternate customer item codes are **most relevant on Doc 2 (invoice/receipt)**, not on quotations. Quotes rarely carry AlterNum; if the assistant needs customer SKUs, prefer Doc 2 history (and AlterKeys master), not Doc 7.

---

## 6. Pricing on conversion (brief)

| Path | Reprice? |
|------|----------|
| AddBaseMoves (PurchQuantFlag=1 sales) | Copies base prices; GPRICE branch only if `@PURCHFLAG=2` |
| InvCopy* | Copies prices |
| RepriceDoc | Explicit batch reprice via GPRICE (manual/job) — not automatic on convert |
| IssueDoc | Calls GPRICE for TREE=2 kit sons; not a full-document reprice of quote lines |

Quotes are **not** automatically recalculated on conversion in the sales BaseDocs path.

---

## 7. Facts vs assumptions

| Statement | Class |
|-----------|-------|
| 33,902 quotations | **FACT** |
| BaseMoveID lineage counts by child type | **FACT** |
| Unique conversion % exact | **UNKNOWN** (need DISTINCT quote StockID query) |
| InvCopy undercounts conversion | **FACT** |
| AlterNum densest on Doc 2 | **FACT** |
| Most quotes never convert | **ASSUMPTION** if relying only on BaseMoveID |
