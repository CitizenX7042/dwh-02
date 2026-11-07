# 10 – Document Lifecycle

**Purpose:** Document create / convert / cancel / delete behavior from selected procedures + Stock/StockMoves triggers.  
**Sources:** `IssueDoc`, `AddBaseMoves`, `PreAddBaseMoves`, `InvCopyDoc`, `InvCopyAllLines`, `InvCopyLine`, `IDelDoc`, `KB_Cancellation`, `InvIssueDocument*`, Stock/StockMoves triggers; prior DocumentsDef volumes.

---

## 1. Call graph (simplified)

```
UI / client
  │
  ├─ create draft Stock + StockMoves (Status often 0)
  │     └─ triggers: StockInsert / StockMovesInsert → Operations('Insert', ID)
  │
  ├─ InvCopyDoc(source → new header)
  │     └─ InvCopyAllLines / InvCopyLine  (copy prices; NO BaseMoveID in copy path)
  │
  ├─ AddBaseMoves(@StockID, @BaseStockID, …)
  │     └─ INSERT StockMoves with BaseMoveID = base line ID
  │        Quantity/BaseQuantity/SupplyQuantity from remaining BaseQuantity
  │        copies Price, DiscountPrc, AlterNum, Unit, …
  │
  ├─ IssueDoc(@StockID, …)     -- large issuer
  │     ├─ may load GetPrice + EXECUTE GPRICE (TREE=2 sons observed)
  │     ├─ UpdateBaseMovesAndItemBalance (reduce SupplyQuantity/BaseQuantity on bases)
  │     ├─ inventory / journal side effects per DocumentsDef
  │     └─ status transitions (Status 0 → 1 typical)
  │
  ├─ InvIssueDocument / InvIssueDocumentCh  -- alternate/issue helpers
  │
  ├─ IDelDoc(@StockId,@status)  -- HARD delete header+lines (+ related)
  │     └─ triggers StockMovesDelete / StockDelete → Operations('Delete')
  │
  └─ KB_Cancellation           -- receipt cancel by issuing offsetting docs
        (not soft-flag on original receipt alone)
```

Updates to existing rows:

```
StockUpdate / StockMovesUpdate triggers
  → Operations(OperationID=row.ID, OperationType='Insert', OperationTable=…)
  ※ typed as Insert, not Update
```

---

## 2. How Stock / StockMoves are inserted

| Path | Behavior |
|------|----------|
| New document | Client/`IssueDoc`/`InvCopyDoc`/`AddBaseMoves` INSERT headers/lines |
| Identity | `Stock.ID`, `StockMoves.ID` IDENTITY |
| Copy path | `InvCopyDoc` INSERTs new `Stock` from source; `InvCopyAllLines` INSERTs lines |
| Base path | `AddBaseMoves` INSERTs lines linked to base |

**FACT:** Copy path sets `DOCUMENTID` from **target** header; copies `PRICE`, `DISCOUNTPRC`, `ALTERNUM`, `UNIT`, `CURRENCYCODE`, etc. from source lines.  
**FACT:** Copy path sets `SUPPLYQUANTITY = QUANTITY` and does **not** set `BaseMoveID` in `InvCopyAllLines`/`InvCopyLine`.

---

## 3. Quotation → Order → Delivery → Invoice

### Verified document IDs (from prior profile)

| Step | DocumentID | Name |
|------|------------|------|
| Quotation | 7 | הצעת מחיר |
| Order | 6 | הזמנה |
| Delivery | 4 | תעודת משלוח |
| Invoice | 1 (primary), 2 | חשבונית מס / מס+קבלה |
| Summary invoice | 37 | חשבונית מס ריכוז |

### Conversion mechanisms

**A. Copy (`InvCopy*`)** — duplicate content into a new document of another type (prices copied, no lineage in these procs).

**B. Base (`AddBaseMoves`)** — create follow-on lines from open base lines:

- Requires `BaseDocs` row for `(DocType=target, BaseDocType=source)`.
- Selects base lines with `Status=1`, `BaseFlag=1`, `BaseQuantity<>0`, `Tree<>2`.
- New line: `BaseMoveID = base.StockMoves.ID`.
- Qty fields seeded from **remaining** `BaseQuantity` (× `@QuantSign`).
- **Copies** `Price`, `DiscountPrc`, `AlterNum`, `AlterName`, `Unit`, VAT fields, etc. (not GPRICE).
- Partial conversion supported by consuming only part of `BaseQuantity` over time.

**C. Issue (`IssueDoc`)** — finalizes draft (`Status=0` lines), updates base open quantities:

```text
new SupplyQuantity/BaseQuantity on base ≈
  old - SUM(child.Quantity * BaseDocs.UpdatFSupplay/UpdatFBase * QuantSign)
```

(clamped at 0; flags when over-consumed)

---

## 4. Lineage fields

| Field | Role (Evidence) |
|-------|-----------------|
| `BaseMoveID` | Child line → parent line ID (`AddBaseMoves`, `IssueDoc` updates) |
| `BaseQuantity` | Remaining qty available to base from / open on a line |
| `SupplyQuantity` | Remaining qty available to supply (delivery-oriented) |
| `PurchQuantity` | Purchase-side open qty variant (`PurchQuantFlag`) |
| `BaseFlag` | Marks lines eligible as bases (`=1` in AddBaseMoves filters) |
| `BaseDocType` | Source document type stamped on child |
| `SourceMoveID` | Present on table; **not central** in reviewed copy/base snippets |
| `IDBeforeChange` | Present on table; **not evidenced** in reviewed procs |

---

## 5. Price / discount / description on conversion

| Field | InvCopy* | AddBaseMoves |
|-------|----------|--------------|
| Price | Copied | Copied from base |
| DiscountPrc | Copied | Copied; some variants fold header disc into line % |
| AlterNum / AlterName | Copied | Copied |
| Unit | Copied | Copied |
| ItemName / Details | Copied | Copied |
| Recalculate via GPRICE | Not in these procs | Not in AddBaseMoves |
| GPRICE on issue | IssueDoc runs GPRICE for **TREE=2** sons | |

**Assumption:** User-entered or previously priced quote lines keep prices through convert unless UI explicitly reprices.

---

## 6. Partial conversions & open quantity

**FACT:** Supported — `AddBaseMoves` only pulls `BaseQuantity<>0`; `IssueDoc` reduces base `SupplyQuantity`/`BaseQuantity` by issued child quantities using `BaseDocs.UpdatFSupplay` / `UpdatFBase`.

Open order/delivery analytics in views (`VOPENORDER`, etc.) align with remaining base/supply quantities and `Status=1`.

---

## 7. Cancellation vs deletion

### `IDelDoc` — **hard delete**

- Verifies `Stock.Status` matches `@status`.
- Deletes related packing/export/extra lines, **DELETE StockMoves**, **DELETE Stock**.
- Triggers write Operations `Delete`.

**Cancelled documents do not remain** after `IDelDoc`.

### Soft cancel fields (`DocCancel*`, `MoveCancel`)

| Field | Writer in SQL | Usage |
|-------|---------------|-------|
| `Stock.DocCancel*` | **`KB_Cancellation`** (~L107266) marks source receipt | Doc1: 4; Doc31: 8; Docs 2–7,37: **0** — **legacy/rare** for sales |
| `StockMoves.MoveCancel` | **No assignments** in `generate_scripts.sql` | Effectively unused |

### `KB_Cancellation` — receipt offset + soft flag

Creates offsetting stock/payment documents **and** sets soft `DocCancel` on the original receipt. Not equivalent to IDelDoc.

### Credits / returns as business cancel

Operational “cancel sale” often = Doc **3** / **5**, not delete or soft flag.

See `14_Document_Status_And_Cancellation.md`.

---

## 8. Whether cancelled docs remain for reporting

| Mechanism | Remains? |
|-----------|----------|
| Soft `DocCancel` | Yes (flagged; rare) |
| Credit/return docs | Yes (new docs) |
| `IDelDoc` | **No** |
| Receipt KB cancel | Original (DocCancel=1) + offsetting docs |

---

## 9. Status model

| Value | Usage |
|------:|-------|
| 0 | Draft / pre-issue (`InvIssueDocument` clears 10→0; `IssueDoc` issues) |
| 1 | Issued / open base eligible |
| 10 | Staging (PreAddBaseMoves / InvCheckStock default) |

`InvChangeStatus` / `InvReturnStatus` park/restore **JurnalTrans** temporary keys — **not** Stock.Status.

Issue validations: `ChBeforIssue` → `ChCredit` / `CheckObligo` (server often non-blocking when alarms=0; UI MessageBox commented). `InvCheckStock` = header existence, not ATP.

---

## 10. Quotation-specific notes

- Doc 7: 33,902 docs; soft cancel 0.
- BaseMoveID: strongest into Doc **1** (≥3,280 quotes); also 6, 4, 2, 37; plus 7→7.
- InvCopy conversions invisible to BaseMoveID — see `15`.
- Sales BaseDocs paths **copy** prices (`PurchQuantFlag=1`); `RepriceDoc` is explicit GPRICE reprice.
- `FatherPriceList`/`SonPriceList`: not read by procedures (report views only).

---

## 11. Additional procedures — status

| Topic | Status |
|-------|--------|
| DocCancel writer | **Resolved** — KB_Cancellation |
| InvIssueDocument vs IssueDoc | **Resolved** — InvIssue* validates then calls IssueDoc |
| BaseDocs matrix | **Resolved** — `13` |
| PreAddBaseMoves | **Resolved** — staging wrapper around AddBaseMoves |
| RepriceDoc / RePricingUpdate | **Resolved** — explicit / temp-table apply |
| ChBeforIssue / CheckObligo / InvCheckStock | **Resolved** — `14` |
| summinv_issue for Doc 37 | Still open if needed |
| Missing non-Stock triggers | Still open — `12`/`08` |

---

## 12. Facts vs assumptions

| Statement | Class |
|-----------|-------|
| AddBaseMoves sets BaseMoveID and copies price/AlterNum | **FACT** |
| InvCopy does not set BaseMoveID | **FACT** |
| IssueDoc reduces base open quantities | **FACT** |
| IDelDoc hard-deletes | **FACT** |
| Update triggers log as OperationType Insert | **FACT** (see doc 11) |
| DocCancel primary cancel for sales | **FALSE** — rare; KB for receipts |
| Quote always bases to order before delivery | **FALSE as exclusive path** — direct 7→1 common in lineage |
| Client blocks Credit/Obligo interactively | **ASSUMPTION** |
