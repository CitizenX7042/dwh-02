# 08 – Required Runtime Logic

**Update:** Final trigger package received and analyzed. No further source-object exports required for discovery close.

**Source discovery status:** **COMPLETE WITH DOCUMENTED LIMITATIONS**.

---

## Analyzed (do not resend)

| Object | Status |
|--------|--------|
| Pricing procs (`GPRICE`, …) | → `09` |
| Lifecycle / issue / cancel / BaseDocs | → `10`, `13`, `14`, `15` |
| Stock* / StockMoves* triggers | → `11`, `12` |
| DocumentsDef* / JurnalTrans* / JurnalTransMoves* triggers | → `11`, `12` |
| PriceLists* / specialprices* / specialpricesmoves* / Discounts* triggers | → `11`, `12` |
| TablesID + CurrentMax + Ops coverage | → `12` |
| `Zero`, AccItemsUpdateLog behavior | → `11` |

---

## Still needed for discovery?

**None** for source discovery.

Optional later (ETL/analytics), not discovery blockers:

| Item | Why |
|------|-----|
| DISTINCT quote conversion query | Exact % |
| TablesID maintenance process | Why LastID lags CurrentMax |
| Client Credit/Obligo confirm | UI vs SQL |
| varieties triggers | Only if varieties enter scope |

---

## Functions

Still low value for pricing/CDC.

---

## Handoff

Proceed to ETL design using documented limitations in `12_Operations_Coverage.md` §8 and `06_Incremental_Load_Assessment.md`.  
Do not design from the assumption that Operations is complete CDC.
