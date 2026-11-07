# 11 – Change Tracking Semantics

**Purpose:** Semantics of `Operations` and `AccItemsUpdateLog` after full trigger analysis (Stock* + DocumentsDef + Jurnal* + pricing masters).  
**See also:** `12_Operations_Coverage.md`.

**Source discovery status:** **COMPLETE WITH DOCUMENTED LIMITATIONS**.

---

## 1. Universal Softwise Operations pattern (FACT)

All analyzed AFTER triggers (enabled, not encrypted, not INSTEAD OF) share one template:

| Event | OperationType written | OperationID | OperationTable |
|-------|----------------------|-------------|----------------|
| INSERT | `Insert` | table key from `Inserted` | parent table name string |
| UPDATE | **`Insert`** (not `Update`) | table key from `Inserted` | same |
| DELETE | `Delete` | table key from `Deleted` | same |

Then gated by:

```sql
SELECT @MID = <Key> FROM Inserted|Deleted   -- SCALAR
SELECT @VSLastId = LastID FROM TablesID WHERE TableName = '<Name>'
IF @MID > @VSLastId RETURN
-- else INSERT Operations … SELECT <Key>, … FROM Inserted|Deleted
```

---

## 2. Key column per table (FACT)

| Parent table | Key used as OperationID / gate | TablesID.TableName |
|--------------|--------------------------------|--------------------|
| Stock | `ID` | `Stock` |
| StockMoves | `ID` | `StockMoves` |
| DocumentsDef | **`DocumentID`** | `DocumentsDef` |
| JurnalTrans | **`TransID`** | `JurnalTrans` |
| JurnalTransMoves | `ID` | `JurnalTransMoves` |
| PriceLists | `ID` | `PriceLists` |
| SpecialPrices | `ID` | `specialprices` |
| SpecialPricesMoves | `ID` | `specialpricesmoves` |
| Discounts | `ID` | `Discounts` |

**DocumentsDef:** OperationID is the document-type code. Explains Insert flood on a small set of OperationIDs (config updates).

---

## 3. Multi-row safety (FACT)

- Logging statement is set-based over `Inserted`/`Deleted`.
- Gate is **scalar** `@MID`.
- Mixed batches across the LastID boundary can be **entirely skipped or entirely logged** — incorrect either way.
- Explicit unsafe single-row assumption on **every** table above.

---

## 4. Implications for incremental loading

| Scenario | Operations signal | Enough alone? |
|----------|-------------------|---------------|
| Insert/update with key ≤ LastID | Insert (touch) | Partial — re-read row |
| Delete with key ≤ LastID | Delete | Removal signal yes |
| Key > LastID | **Silent** | Blind — slice/reconcile |
| Field-level diff | Never | Must read source |
| PriceLists mostly ≤ LastID | Mostly usable touch | Reconcile small tail |
| SpecialPrices\* / Discounts | Incomplete | **Full/slice reload** |

**Verdict:** Operations = **partial touch/delete log**, not typed CDC, not complete.

---

## 5. AccItemsUpdateLog semantics

| Finding | Class |
|---------|-------|
| Type 1 = Items, Type 2 = Accounts field edits | **FACT** |
| StationId / UseFid present | **FACT** |
| `Zero` TRUNCATES | **FACT** |
| No SQL INSERT in generate_scripts.sql | **FACT** |
| Client writes log | **ASSUMPTION (High)** |

Not part of Operations.

---

## 6. Soft cancel vs change tracking

| Source | Role |
|--------|------|
| Soft `DocCancel*` | Rare; `KB_Cancellation` |
| `MoveCancel` | No SQL writer |
| `IDelDoc` | Hard delete → Operations Delete (if gated) |

---

## 7. Recommended CDC interpretation (assessment only — not ETL design)

1. Treat Ops Insert as upsert-touch; Delete as remove; always join to source tables.  
2. Never trust Ops alone for IDs > `TablesID.LastID`.  
3. Pricing masters: Ops hint for PriceLists; scheduled reload for SpecialPrices\*/Discounts.  
4. AccItemsUpdateLog watermark + reconcile for Items/Accounts cards.  
5. Do not use `Zero` as a feeder.

---

## 8. Facts vs assumptions

| Statement | Class |
|-----------|-------|
| All listed Update triggers log OperationType Insert | **FACT** |
| DELETE logs as Delete | **FACT** |
| TablesID gate on all analyzed triggers | **FACT** |
| DocumentsDef OperationID = DocumentID | **FACT** |
| JurnalTrans OperationID = TransID | **FACT** |
| Scalar gate unsafe for multi-row | **FACT** |
| CurrentMax ≫ LastID on core transactional + SpecialPrices | **FACT** |
| Client writes AccItemsUpdateLog | **ASSUMPTION** |
