# 14 – Document Status And Cancellation

**Purpose:** Status transitions, issue validations, and cancel/delete mechanisms.  
**Sources:** `InvIssueDocument`, `InvIssueDocumentCh`, `ChBeforIssue`, `ChCredit`, `CheckObligo`, `InvCheckStock`, `InvChangeStatus`, `InvReturnStatus`, `IDelDoc`, `KB_Cancellation`, soft-cancel usage counts, `generate_scripts.sql` searches for `DocCancel` / `MoveCancel`.

---

## 1. Document / line Status (Stock / StockMoves)

| Status | Meaning in runtime procs | Class |
|-------:|--------------------------|-------|
| **0** | Draft / pre-issue; `InvIssueDocument` clears Status=10→0 then calls `IssueDoc`; `IssueDoc` works on Status=0 children | **FACT** |
| **1** | Issued / open base eligible (`AddBaseMoves` filters Status=1 bases) | **FACT** |
| **10** | Staging / pre-issue holding (PreAddBaseMoves marks related moves; InvIssueDocument resets 10→0; InvCheckStock default expects 10) | **FACT** |

### `InvChangeStatus` / `InvReturnStatus` — **not** document Status

| Proc | Lines | Actual behavior |
|------|------:|-----------------|
| `InvChangeStatus` | 95804–95851 | Parks `JurnalTrans` rows: `STOCKID→888888`, `BATCHNO→7777`, `STATUS→22` for `BATCHNO=9999` |
| `InvReturnStatus` | 100398–100444 | Restores: `BATCHNO→9999`, `STOCKID→@StockID`, `STATUS→1` |

**FACT:** These manage temporary journal parking during issue, **not** Stock.Status workflow dictionary.

---

## 2. Issue call chain

```
InvIssueDocument (@STOCKID)
  ├─ abort if InterErrMesg blocking errors (tbl=1)
  ├─ UpInvTotal
  ├─ InvIssueDocumentCh
  │     ├─ chDocDates
  │     ├─ UpdateMoveJurAcc
  │     ├─ ChBeforIssue
  │     │     ├─ tax year / value date checks
  │     │     ├─ ChCredit          (credit limit)
  │     │     ├─ CheckObligo       (obligo)
  │     │     ├─ InvChZelemsInDoc, CheckCounterInDoc, …
  │     │     ├─ journal share %, VAT transtype, totals, budget, print format
  │     │     └─ sets @res=0 block / @res=1 continue
  │     └─ KBchecksBeforeInv (Doc 2/62/87)
  ├─ optional KbDocTotal match for Doc 2
  ├─ BEGIN TRAN
  ├─ Status 10 → 0 on moves + header
  └─ IssueDoc (… Status→1 + inventory/journal)
```

Lines: `InvIssueDocument` 97664–97848; `InvIssueDocumentCh` 97849–97959; `ChBeforIssue` 61619–61928.

---

## 3. Validations — block vs warn

| Check | Procedure | Blocks issue? | Notes |
|-------|-----------|---------------|-------|
| Existing InterErrMesg (err≠1) | InvIssueDocument | **Yes** (`return 0`) | Pre-existing messages |
| Document dates | `chDocDates` via InvIssueDocumentCh | **Yes** if `@res=0` | |
| Income/expense account on lines | `UpdateMoveJurAcc` | **Yes** | |
| Copies required when FixNumerator | ChBeforIssue | **Yes** (err 75) | |
| ValueDate outside tax year | ChBeforIssue | **Yes** (err 53) | |
| ValueDate ≠ today | ChBeforIssue | **Warn only** — `InvUpdateErrorMessage …,1,'Stock.ValueDate',74` then **continues** | |
| Credit limit | `ChCredit` | **Only if CreditAlarm≠0 path were active** — see §4 | Server currently soft |
| Obligo | `CheckObligo` | Same pattern — see §5 | |
| Counters / Z-elems / income acts / doc# | ChBeforIssue children | **Yes** if `@res=0` | |
| Journal payment share ≠100% | ChBeforIssue | **Yes** when UpdatFJurnal≠0 | |
| Zero total with journal | ChBeforIssue | **Yes** | |
| Budget / rate / print format | ChBeforIssue | **Yes** when configured | |
| Doc 2 invoice≠receipt total | InvIssueDocument | **Yes** (err 89) | |
| Stock row exists at Status | `InvCheckStock` | **Yes** if count=0 | Default Status=10 — existence check, **not** ATP inventory |

**FACT:** `InvCheckStock` does **not** check warehouse availability; it checks that a Stock header exists with the given Status.

---

## 4. Credit limit — `ChCredit` (61929–62066)

- Runs only if `SalesDoc=1` and `UpdatFJurnal≠0` and DocumentID not in (2, 62).
- Computes `Dev = MaxCredit*rate + Balance − tftal*MainRate`.
- If `CreditAlarm=0` and `Dev<0` → still `@Res=1` (continue). Interactive MessageBox paths for CreditAlarm 1/2 are **commented out**.

**FACT (server):** With current script, credit overrun does **not** hard-block when `CreditAlarm=0`; alarm modes 1/2 UI confirmations are not active in SQL.  
**ASSUMPTION:** Client may still enforce using the same CompanyDefenitions flags.

---

## 5. Obligo — `CheckObligo` (62275–62415)

- Skips non-sales (`SalesDoc≠1` → `@res=1`).
- Loads current obligo via `invGetObligo` / `InvMaxObligo`.
- If `ObligoAlarm=0` and `Dev>0` → `@res=1` (continue, no block).
- Interactive ObligoAlarm 1/2 MessageBox logic is **commented out**; procedure ends `@res=1`.

**FACT:** Server-side obligo does not hard-fail in the shipped SQL when alarms are off / commented.  
**ASSUMPTION:** Client may prompt.

---

## 6. Cancellation mechanisms compared

### A. Soft cancel — `Stock.DocCancel*`

| Item | Finding |
|------|---------|
| Who writes | **Only** `KB_Cancellation` in `generate_scripts.sql` (`UPDATE Stock SET DocCancel=1, DocCancelDate, DocCancelUsefID, DocCancelTime` ~L107266) |
| Context | Marks the **original receipt** when cancelling via KB path |
| Usage (user counts) | Doc1: **4**/131974; Doc31: **8**/23832; Docs 2–7,37: **0** |
| Verdict | **Legacy / rare** for sales docs; active mainly as KB receipt flag |

### B. `StockMoves.MoveCancel`

| Item | Finding |
|------|---------|
| Writers in SQL | **None** — only column + default in schema; no `MoveCancel=` assignments in procedures |
| Usage | Prior profiles showed negligible / unused |
| Verdict | **Unused or client-only**; not an active SQL soft-cancel path |

### C. Hard delete — `IDelDoc` (~90157–90336)

- Deletes related extras, **DELETE StockMoves**, **DELETE Stock**.
- Document **does not remain**.
- Triggers → Operations `Delete`.

### D. Credit / return documents

- Doc **3** (credit) / Doc **5** (return) are **new documents**, often BaseMoveID-linked from 1/2/4.
- Original invoice/DN remains; economic reverse via new doc.

### E. `KB_Cancellation` offset documents

- Creates offsetting stock/payment documents for receipt cancellation (cash/cheque/credit paths).
- Additionally sets soft `DocCancel` on the source receipt (see A).
- Not the same as IDelDoc; original + offsets remain for audit.

---

## 7. Soft cancel vs others (summary)

| Mechanism | Leaves original row? | Typical volume | Written by |
|-----------|---------------------|----------------|------------|
| Soft DocCancel | Yes (flagged) | Very rare (sales); rare on receipts | `KB_Cancellation` (+ possible client) |
| MoveCancel | Yes if set | Effectively unused in SQL | Unknown / unused |
| IDelDoc | **No** | Draft cleanup | `IDelDoc` |
| Credit/Return | Yes + new reverse doc | Material (12k credits, 1.8k returns) | Document issue |
| KB offset | Yes + new offset docs | Receipt cancel workflow | `KB_Cancellation` |

---

## 8. Facts vs assumptions

| Statement | Class |
|-----------|-------|
| Issue path InvIssueDocument → Ch → IssueDoc | **FACT** |
| InvChangeStatus parks journals, not Stock.Status | **FACT** |
| InvCheckStock ≠ inventory ATP | **FACT** |
| DocCancel written by KB_Cancellation | **FACT** |
| MoveCancel not written in SQL procs | **FACT** |
| Soft cancel is legacy for Doc 1–7 | **FACT** (usage) |
| Client enforces CreditAlarm/ObligoAlarm interactively | **ASSUMPTION** |
