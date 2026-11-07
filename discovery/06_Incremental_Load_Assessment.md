# 06 – Incremental Load Assessment

**Update:** Remaining trigger bodies analyzed (`triggers_definition.xlsx`). Same Softwise pattern on DocumentsDef, Jurnal*, PriceLists, SpecialPrices*, Discounts.

**Source discovery status:** **COMPLETE WITH DOCUMENTED LIMITATIONS**.

---

## 1. Operations (FACT — all CDC-relevant tables)

### Behavior (every Insert/Update/Delete trigger)

- INSERT → Operations `Insert`
- UPDATE → Operations **`Insert`** (not `Update`)
- DELETE → Operations `Delete`
- Skipped when scalar key > `TablesID.LastID`
- OperationID = `ID` except **DocumentsDef→DocumentID**, **JurnalTrans→TransID**

### Live watermark gap

| Table | LastID | CurrentMaxID | Class |
|-------|-------:|-------------:|-------|
| Stock | 195,729 | 403,281 | Beyond / partial |
| StockMoves | 874,954 | 1,867,667 | Beyond / partial |
| JurnalTrans | 266,447 | 485,084 | Beyond / partial |
| JurnalTransMoves | 676,048 | 1,186,869 | Beyond / partial |
| PriceLists | 24,815 | 25,764 | Mostly inside |
| SpecialPrices | 3,409 | 7,949 | Beyond |
| SpecialPricesMoves | 3,393 | 7,933 | Beyond |
| Discounts | 11 | unknown | Unreliable / likely blind |
| DocumentsDef | 143 | DocumentID key | Inside for active types |

**Do not assume Operations is complete.**

### Verdict

| Question | Answer |
|----------|--------|
| Reliable typed CDC? | **No** — updates as Insert |
| Useful touch log? | **Yes**, only inside gated key range |
| Blind spot | Keys above `TablesID.LastID`; scalar multi-row gate |
| All trigger bodies known? | **Yes** for Stock* + DocumentsDef + Jurnal* + pricing masters |

Full detail: `11_Change_Tracking_Semantics.md`, `12_Operations_Coverage.md`.

---

## 2. AccItemsUpdateLog

| Question | Answer |
|----------|--------|
| Tracks Items/Accounts field edits? | **Yes** |
| Written by `Zero`? | **No** — truncates |
| SQL INSERT writer? | **None** in generate_scripts |
| Writer | **ASSUMPTION (High):** client |
| Difficulty | Medium + full reconcile |

---

## 3. Stock / StockMoves incremental posture

1. Ops touch (Insert/Delete) inside LastID.  
2. Re-pull touched IDs from base tables.  
3. **Must** supplement ValueDate/ID slices for IDs > LastID.  
4. Soft DocCancel via column (rare).  

**Difficulty:** Hard for complete coverage.

---

## 4. Pricing masters

| Table | Ops as change signal | Cache invalidation from Ops? |
|-------|----------------------|------------------------------|
| PriceLists | Mostly usable | Soft signal OK + reconcile tail |
| SpecialPrices / Moves | Incomplete (beyond LastID) | **Not sufficient alone** |
| Discounts | Unreliable (LastID=11) | **Not sufficient alone** |

Prefer scheduled reload/reconcile of pricing masters; Ops is an optional accelerator for PriceLists only.

---

## 5. Bottom line

Operations is a **partial touch/delete feed with updates labeled Insert**, gated by `TablesID`, with an unsafe scalar multi-row gate. AccItemsUpdateLog is a separate client field audit. ETL must plan periodic reconciliation for all high-volume and pricing tables beyond LastID.
