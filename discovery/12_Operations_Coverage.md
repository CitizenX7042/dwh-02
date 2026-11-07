# 12 – Operations Coverage

**Purpose:** Classify how complete `Operations` is as a change feed, using `TablesID`, current max IDs, Operations aggregates, and **all** relevant trigger definitions.  
**Sources:** `TablesID.xlsx`, `Table_currentMaxID.xlsx`, `Operations coverage by table.xlsx`, `Triggers.xlsx`, `triggers_definition.xlsx`, `trigger_is encrypted.xlsx`, `trigger_verify nothing was missed.xlsx`, `generate_scripts.sql` (0 `CREATE TRIGGER`).

**Source discovery status:** **COMPLETE WITH DOCUMENTED LIMITATIONS** (see §8).

---

## 1. Trigger inventory (verified)

| Parent table | Triggers | Disabled? | Encrypted? | Body source |
|--------------|----------|-----------|------------|-------------|
| `Stock` | I/U/D | No | No | `Triggers.xlsx` |
| `StockMoves` | I/U/D | No | No | `Triggers.xlsx` |
| `DocumentsDef` | I/U/D | No | No | `triggers_definition.xlsx` |
| `JurnalTrans` | I/U/D | No | No | `triggers_definition.xlsx` |
| `JurnalTransMoves` | I/U/D | No | No | `triggers_definition.xlsx` |
| `PriceLists` | I/U/D | No | No | `triggers_definition.xlsx` |
| `SpecialPrices` | I/U/D | No | No | `triggers_definition.xlsx` |
| `SpecialPricesMoves` | I/U/D | No | No | `triggers_definition.xlsx` |
| `Discounts` | I/U/D | No | No | `triggers_definition.xlsx` |
| `varieties` | I/U/D | No | No | Listed in verify; **not analyzed** (out of scope) |

**FACT:** Softwise uses one identical template on every table; only the key column and `TablesID.TableName` string differ.

---

## 2. Per-table trigger matrix (DocumentsDef … Discounts)

Shared pattern for every Insert/Update/Delete trigger:

```text
DECLARE @MID INT, @VSLastId INT
SELECT @MID = <KeyCol> FROM Inserted|Deleted          -- SCALAR
SELECT @VSLastId = LastID FROM TablesID WHERE TableName = '<Name>'
IF @MID > @VSLastId RETURN
INSERT Operations (OperationID, OperationType, OperationTable)
SELECT <KeyCol>, '<Insert|Delete>', '<Name>' FROM Inserted|Deleted
```

| Parent | Event triggers | OperationTable | OperationID source | UPDATE→Insert? | DELETE typed? | TablesID.TableName |
|--------|----------------|----------------|--------------------|----------------|---------------|--------------------|
| DocumentsDef | I / U / D | `DocumentsDef` | **`DocumentID`** | **Yes** | Yes (`Delete`) | `DocumentsDef` |
| JurnalTrans | I / U / D | `JurnalTrans` | **`TransID`** | **Yes** | Yes | `JurnalTrans` |
| JurnalTransMoves | I / U / D | `JurnalTransMoves` | **`ID`** | **Yes** | Yes | `JurnalTransMoves` |
| PriceLists | I / U / D | `PriceLists` | **`ID`** | **Yes** | Yes | `PriceLists` |
| SpecialPrices | I / U / D | `specialprices` | **`ID`** | **Yes** | Yes | `specialprices` |
| SpecialPricesMoves | I / U / D | `specialpricesmoves` | **`ID`** | **Yes** | Yes | `specialpricesmoves` |
| Discounts | I / U / D | `Discounts` | **`ID`** | **Yes** | Yes | `Discounts` |

Stock / StockMoves (prior): same pattern with key `ID`, OperationTable `Stock` / `StockMoves`.

### DocumentsDef flood explained (FACT)

`OperationID = DocumentID` (type code), not a surrogate row identity. Updates to document-type config re-log the same DocumentID as `Insert`. With `LastID=143`, all active DocumentIDs (1,2,4,6,7,31,37,…) are ≤ LastID → **every config touch is logged** → explains ~80k Insert ops on ~131 distinct OperationIDs.

---

## 3. Multi-row safety (all analyzed triggers)

| Behavior | Verdict |
|----------|---------|
| Final `INSERT…SELECT` from `Inserted`/`Deleted` | Set-based — **would** log all rows **if** gate passes |
| Gate uses scalar `@MID = SELECT key FROM Inserted|Deleted` | **Unsafe** single-row assumption |
| Mixed batch (some keys ≤ LastID, some >) | Entire trigger may **RETURN** (miss all) or proceed (log all including those that should have been skipped) depending on which key SQL Server assigns to `@MID` |
| Partial logging of mixed batch | **Not** implemented — all-or-nothing relative to scalar gate |

**FACT:** Same unsafe pattern on DocumentsDef, Jurnal*, PriceLists, SpecialPrices*, Discounts, Stock*.

---

## 4. TablesID vs CurrentMaxID (coverage classes)

| Table | LastID | CurrentMaxID | Class | Touch-log usable? |
|-------|-------:|-------------:|-------|-------------------|
| Stock | 195,729 | 403,281 | Beyond / partial | Partial only |
| StockMoves | 874,954 | 1,867,667 | Beyond / partial | Partial only |
| JurnalTrans | 266,447 | 485,084 | Beyond / partial | Partial only |
| JurnalTransMoves | 676,048 | 1,186,869 | Beyond / partial | Partial only |
| PriceLists | 24,815 | 25,764 | Mostly inside (small tail) | Mostly yes |
| specialprices | 3,409 | 7,949 | **Beyond** | **No** for newest IDs |
| specialpricesmoves | 3,393 | 7,933 | **Beyond** | **No** for newest IDs |
| Discounts | 11 | *(not dumped)* | **Likely blind / unclear** | Unreliable if ID>11 |
| DocumentsDef | 143 | N/A (DocumentID key) | Inside for DocumentID≤143 | Yes for active types |

**Do not assume Operations is complete.**

---

## 5. CDC implications by table

| Table | Insert detectable? | Update detectable? | Delete detectable? | Periodic reconcile? |
|-------|--------------------|--------------------|--------------------|---------------------|
| Stock / StockMoves | Only if ID≤LastID | As Insert touch | Yes if gated | **Required** |
| JurnalTrans / Moves | Only if key≤LastID | As Insert | Yes if gated | **Required** |
| DocumentsDef | Yes (DocumentID≤143) | As Insert | Yes | Optional (low churn) |
| PriceLists | Mostly | As Insert | Yes | Recommended (tail beyond LastID) |
| SpecialPrices / Moves | **Incomplete** | Incomplete | Incomplete | **Required** |
| Discounts | Only ID≤11 | Same | Same | **Required** until LastID/CurrentMax known |

---

## 6. Pricing impact

| Master | Reliably detectable via Operations? | Pricing cache invalidation from Ops? |
|--------|--------------------------------------|--------------------------------------|
| PriceLists | **Mostly** (small ID gap) | **Possible** as soft signal; still re-read row; reconcile tail IDs > LastID |
| SpecialPrices | **No** for IDs > 3409 | **Not reliable** alone |
| SpecialPricesMoves | **No** for IDs > 3393 | **Not reliable** alone |
| Discounts | **Doubtful** (LastID=11; absent from Ops coverage extract) | **Not reliable** alone |

**FACT:** Triggers fire and write the Softwise touch pattern, but **TablesID watermarks make SpecialPrices\* and likely Discounts incomplete**.  
**ETL implication:** Ops can hint “something changed” for PriceLists; for SpecialPrices/Discounts prefer scheduled full/slice reload of pricing masters, not Ops-only invalidation.

Pricing **precedence** (GPRICE order) is unchanged by these triggers.

---

## 7. AccItemsUpdateLog (unchanged)

No Operations involvement. Client field audit; `Zero` truncates. Separate channel for Items/Accounts attribute edits.

---

## 8. Source discovery status

### COMPLETE WITH DOCUMENTED LIMITATIONS

Source discovery for Softwise DANOR13 is **closed** for documented objects, processes, pricing, conversion, cancel, and CDC semantics.

### Limitations that ETL design must handle

1. **Operations is a partial touch log** — Update→Insert; no field-level diff; gated by `TablesID.LastID`.  
2. **CurrentMax ≫ LastID** on Stock, StockMoves, JurnalTrans, JurnalTransMoves, SpecialPrices, SpecialPricesMoves.  
3. **Scalar TablesID gate** can miss or over-include multi-row mixed batches.  
4. **PriceLists** mostly covered; **SpecialPrices\*** and **Discounts** not reliable from Ops alone.  
5. **InvCopy** conversions have no `BaseMoveID` — quote conversion undercount if Ops/lineage-only.  
6. **AccItemsUpdateLog** writer not proven in SQL (client assumed); truncated by `Zero`.  
7. **Soft DocCancel** rare; **MoveCancel** unused in SQL.  
8. **CreditAlarm / ObligoAlarm** interactive blocks commented in SQL — client may still enforce.  
9. **varieties** triggers exist but were out of this analysis scope.  
10. **Unique quote conversion %** still approximate without DISTINCT query (optional refinement).

No further source-object exports required to start ETL design, provided the limitations above are treated as requirements.
