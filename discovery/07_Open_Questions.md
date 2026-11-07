# 07 – Open Questions

**Update:** Final trigger supplement analyzed. Source discovery closed with documented limitations.

**Source discovery status:** **COMPLETE WITH DOCUMENTED LIMITATIONS**.

---

## Resolved in this phase

| # | Resolution | Evidence |
|---|------------|----------|
| R13–R31 | Prior resolutions | docs 09–15 |
| R32 | DocumentsDef/Jurnal*/Price*/Special*/Discounts triggers = same Softwise Ops pattern | `triggers_definition.xlsx` |
| R33 | UPDATE→Insert; DELETE→Delete on all those tables | trigger bodies |
| R34 | DocumentsDef OperationID = DocumentID | trigger body |
| R35 | JurnalTrans OperationID = TransID | trigger body |
| R36 | All use TablesID scalar gate | trigger bodies |
| R37 | Triggers not encrypted / not disabled | companion Excels |

---

## Remaining (not blocking discovery close)

These are **ETL-design / optional refinement** items, not missing source definitions:

### Carry into ETL design (limitations)

1. Ops incomplete for keys > TablesID.LastID (Stock, Moves, Jurnal*, SpecialPrices*).  
2. Scalar multi-row TablesID gate unsafe.  
3. SpecialPrices*/Discounts not reliable for Ops-only pricing cache invalidation.  
4. InvCopy quote conversions invisible to BaseMoveID.  
5. AccItemsUpdateLog client writer (High assumption).  
6. CreditAlarm/ObligoAlarm may still be enforced in UI.  
7. How/when TablesID.LastID is advanced (ops process unknown).  

### Optional analytics refinements (P2)

8. Exact DISTINCT quote conversion %  
9. Full IssueDoc inventory posting map (if GL grain needed)  
10. summinv_issue for Doc 37  
11. Manufacturer / InvPdfFiles / GPFLAG dictionary / empty wiz schemas  
12. varieties triggers (exist; out of prior scope)

---

## Next phase

Source discovery handoff is complete. Next work is **ETL / DWH design**, which must encode the limitations listed in `12_Operations_Coverage.md` §8.

Do **not** request further trigger or procedure exports unless a new object appears outside the analyzed set.
