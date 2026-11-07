# 13 – BaseDocs Conversion Matrix

**Purpose:** Verified conversion configuration for sales document types 7 / 6 / 4 / 1 / 2 / 3 / 5 / 37, separated from paths that are only possible in code.  
**Sources:** `BaseDocs.xlsx` (122 rows), `AddBaseMoves` / `PreAddBaseMoves` / `IssueDoc` / `InvCopy*` in `generate_scripts.sql`.

---

## 1. Two conversion mechanisms (reminder)

| Mechanism | Lineage | Price behavior | Config gate |
|-----------|---------|----------------|-------------|
| **BaseMoveID** (`PreAddBaseMoves` → `AddBaseMoves` → issue reduces open qty) | Child `StockMoves.BaseMoveID` = parent line ID | Normally **copies** base Price/Discount/AlterNum; GPRICE only if `@PURCHFLAG=2` (purchase special path) | Requires `BaseDocs` row for `(DocType=target, BaseDocType=source)` |
| **Copy** (`InvCopyDoc` / `InvCopyAllLines` / `InvCopyLine`) | **No** `BaseMoveID` | Copies prices | UI/type choice; not gated by BaseDocs in these procs |

**Configured paths below** = rows present in `BaseDocs`.  
**Code-possible but not configured** = InvCopy between types without BaseDocs, or BaseDocs for unused DocumentIDs.

---

## 2. Core sales matrix (configured BaseDocs pairs)

Flags (all listed pairs unless noted): `PurchQuantFlag=1`, `CancelBaseQnt=0`.

| BaseDocType | Base name | DocType | Doc name | QuantSign | UpdatFBase | UpdatFSupplay | ZeroBaseQuant | CancelBaseQnt | Partial? | Qty reduced on source | Relationship |
|------------:|-----------|--------:|----------|----------:|-----------:|--------------:|--------------:|--------------:|----------|----------------------|--------------|
| 7 | הצעת מחיר | 6 | הזמנה | 1 | 1 | 1 | 1 | 0 | Yes | BaseQuantity + SupplyQuantity | **BaseMoveID** |
| 7 | | 4 | תעודת משלוח | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 7 | | 1 | חשבונית מס | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 7 | | 2 | חשבונית מס/קבלה | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 7 | | 37 | חשבונית מס ריכוז | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 7 | | 7 | הצעת מחיר | 1 | 1 | 1 | 1 | **1** | Yes | Base + Supply | BaseMoveID (quote→quote; CancelBaseQnt=1) |
| 6 | הזמנה | 4 | תעודת משלוח | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 6 | | 1 | חשבונית מס | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 6 | | 2 | חשבונית מס/קבלה | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 6 | | 37 | חשבונית מס ריכוז | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 6 | | 6 | הזמנה | 1 | 1 | 1 | 1 | **1** | Yes | Base + Supply | BaseMoveID (order→order) |
| 4 | תעודת משלוח | 1 | חשבונית מס | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 4 | | 2 | חשבונית מס/קבלה | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 4 | | 37 | חשבונית מס ריכוז | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 4 | | 5 | החזרה | 1 | 1 | **0** | 0 | 0 | Yes* | **Base only** (UpdatFSupplay=0) | BaseMoveID |
| 1 | חשבונית מס | 3 | חשבונית מס זיכוי | 1 | 1 | **0** | 0 | 0 | Yes* | **Base only** | BaseMoveID |
| 2 | חשבונית מס/קבלה | 3 | זיכוי | 1 | 1 | **0** | 0 | 0 | Yes* | **Base only** | BaseMoveID |
| 37 | ריכוז | 3 | זיכוי | 1 | 1 | **0** | 0 | 0 | Yes* | **Base only** | BaseMoveID |
| 5 | החזרה | 2 | מס/קבלה | **−1** | 1 | 1 | 1 | 0 | Yes | Base + Supply (signed) | BaseMoveID |
| 5 | | 3 | זיכוי | 1 | 1 | 1 | 1 | 0 | Yes | Base + Supply | BaseMoveID |
| 5 | | 4 | משלוח | 1 | 1 | **0** | 0 | 0 | Yes* | **Base only** | BaseMoveID |
| 5 | | 37 | ריכוז | **−1** | 1 | 1 | 1 | 0 | Yes | Base + Supply (signed) | BaseMoveID |

\*Partial conversion is still supported by open `BaseQuantity`/`SupplyQuantity` mechanics whenever the corresponding UpdatF* flag is 1; when UpdatFSupplay=0, only BaseQuantity is reduced on issue (`IssueDoc` / UpdateBaseMoves logic).

### Flag meanings (runtime)

| Flag | Role in conversion |
|------|--------------------|
| `UpdatFBase=1` | Issuing child reduces parent `BaseQuantity` |
| `UpdatFSupplay=1` | Issuing child reduces parent `SupplyQuantity` |
| `PurchQuantFlag=1` | Sales open-qty mode (not the purchase `@PURCHFLAG=2` GPRICE branch in `AddBaseMoves`) |
| `QuantSign` | Sign applied when seeding/reducing quantities |
| `ZeroBaseQuant=1` | Related to zeroing/closing base open qty behavior when fully consumed |
| `CancelBaseQnt=1` | Same-type conversions (7→7, 6→6) — cancel/replace open qty semantics |

---

## 3. Partial conversion (verified)

**FACT:** Supported for BaseMoveID paths:

- `AddBaseMoves` only pulls base lines with remaining open qty (`BaseQuantity<>0` / purchase variant).
- `IssueDoc` reduces parent open quantities by child issued qty × BaseDocs flags.
- Multiple children can consume one parent line over time.

---

## 4. Which source quantity is reduced?

| Situation | Field(s) reduced on **source** line |
|-----------|--------------------------------------|
| Forward sales convert (7→6/4/1/2/37, 6→4/1/2/37, 4→1/2/37) | `BaseQuantity` **and** `SupplyQuantity` |
| Credit from invoice (1/2/37→3), DN→return (4→5), return→DN (5→4) | Primarily `BaseQuantity` (`UpdatFSupplay=0`) |
| Return → invoice paths with QuantSign −1 | Both, with negative sign |

---

## 5. Paths configured but secondary / low business use

- Direct **7→1 / 7→2 / 7→37** and **6→1 / 6→2** are **configured** (skip order or delivery). Lineage data shows they occur (see `15_Quotation_Conversion_Analysis.md`).
- Doc **37** is configured as a target from 7/6/4/5 but volume is low vs Doc 1.

---

## 6. Copy-based paths (not in BaseDocs matrix)

| Path | Evidence | Visible in BaseMoveID lineage? |
|------|----------|--------------------------------|
| Any type → any type via `InvCopy*` | `InvCopyDoc` / `InvCopyAllLines` | **No** |
| Quote lines copied into order/invoice without AddBaseMoves | Same | **No** |

Treat copy conversions as **code-possible / UI-driven**, not BaseDocs-configured.

---

## 7. Runtime helpers

| Procedure | Lines (approx) | Role |
|-----------|----------------|------|
| `PreAddBaseMoves` | 118307–118431 | Resolves `ITempBaseDoc.baseStockId`; loops bases; calls `AddBaseMoves` per base StockID; marks staging lines Status=10 |
| `AddBaseMoves` | 54086–55446 | Inserts child lines with `BaseMoveID`; copies price/AlterNum; optional GPRICE when `@PURCHFLAG=2` |
| `IssueDoc` | 101160–105483 | Issues draft; updates base open quantities using BaseDocs flags |

---

## 8. Facts vs assumptions

| Statement | Class |
|-----------|-------|
| Matrix pairs above exist in BaseDocs | **FACT** |
| PurchQuantFlag=1 on these sales pairs | **FACT** |
| BaseMoveID path copies prices for PurchFlag≠2 | **FACT** |
| Partial conversion supported | **FACT** |
| UI always prefers 7→6→4→1 | **ASSUMPTION** (data shows direct 7→1 also) |
| All InvCopy conversions require BaseDocs | **FALSE** — copy is independent |
