# 09 – Pricing Engine

**Purpose:** Reverse-engineer Softwise deterministic pricing used for quotations, orders, invoices, and related sales docs.  
**Sources:** `GPRICE`, `GetHighSPrice`, `GetMinSPrice`, `GetSplitSPrice`, `GetAllDocPrices`, `CheckMinPrice`, and `IssueDoc` call sites from `C:\Danyor_project\generate_scripts.sql`.

**Rules:** Facts vs assumptions separated. Small quotes only. No replacement pricing SQL.

---

## 1. Procedure call hierarchy

```
Application / IssueDoc / document UI
   │
   │  INSERT rows into dbo.GetPrice
   │  (StationID, AccountKey, ItemKey, Quantity, DatF, DocumentID, …)
   │
   ▼
GPRICE(@STATIONID, @ASSIGN, @Split=0, @RESULT OUT)
   │
   ├── [branch/kupa shortcut] AgentWarehouseNames.PriceListID  (Sort=6)
   │         → PriceLists by that list only → write GetPrice → RETURN path
   │
   └── [normal path @FlagByBranch=0]
         ├── Discounts matrix (account × item discount code)
         ├── PriceLists (via Discounts.PriceListNumber + DatF ≤ DatF)
         ├── Items.DiscountPrc overlay (sales docs)
         ├── GetMinSPrice   (SpecialPrices.MinDebit=1 floor deals)
         ├── GetHighSPrice  (SpecialPrices.CalcMethod=0 qty-break)
         ├── GetSplitSPrice (SpecialPrices.CalcMethod=1 split ranges)
         ├── (optional) same specials via Accounts.AssignKey
         ├── (optional) specials on DUMI=1 “dummy” accounts (sales docs)
         ├── Items.Price / Items.PurchPrice fallback
         └── UPDATE dbo.GetPrice with PRICE, COIN, DISCOUNTPRC, COMMISIONPRC, GPFLAG

IssueDoc (tree sons only in observed section)
   DELETE/INSERT GetPrice for StockMoves TREE=2
   EXECUTE GPRICE @STATION_ID, 0
   UPDATE StockMoves FROM GetPrice

GetAllDocPrices(@StockID,@AccountKey,@ItemKey)   -- historical lookup UI helper
   → TEMPGetAlLPrices (last prices by doc family, incl. Doc 7 quotations)

CheckMinPrice(@StockID)   -- validation only, not price resolution
   → TempMinPrice vs PurchPrice or PriceListAlarmID
```

**Referenced but not a priced engine input here:** `Stock.FatherPriceList` / `SonPriceList` — **not read by GPRICE**.  
**Assumption:** list choice for normal path is via `Discounts.PriceListNumber`, not Stock header lists (unless the client preloads something else into `GetPrice`).

---

## 2. Source precedence (normal sales path)

Order of application inside `GPRICE` when `@FlagByBranch=0`:

| Step | Source | What it sets | GPFLAG marker (Evidence) |
|-----:|--------|--------------|---------------------------|
| 0 | Staging `GetPrice` | inputs only; price unset | 0 |
| 1 | `Discounts` on `AccountKey` × `Items.DiscountCode` | `DiscountPrc`, `CommisionPrc` | **10** |
| 1b | Same via `Accounts.AssignKey` if `@ASSIGN=2` | discount/commission | **11** |
| 2 | `PriceLists` joined through `Discounts.PriceListNumber` with `PriceLists.DatF ≤ GetPrice.DatF` (latest) | `Price`, `Coin`, may refresh discount/commission | **41** (assign path **42**) |
| 3 | `Items.DiscountPrc` if `DocumentsDef.SalesDoc=1` and item discount ≠ 0 | **overwrites** `DiscountPrc` | (keeps prior flag) |
| 4 | `GetMinSPrice` (`MinDebit=1`, qty below threshold) | special floor price | **50+AccType** |
| 5 | `GetHighSPrice` (`CalcMethod=0`) best qty-break ≤ qty | special price + move discount | **50+AccType** |
| 6 | `GetSplitSPrice` (`CalcMethod=1`) weighted split | blended price; may split lines | **53+** / **60+** |
| 5–6b | Repeat specials on AssignKey / DUMI accounts if still `GPFLAG<50` | | |
| 7 | `Items.Price` + `Items.Currency` if still `GPFLAG<20` and `SalesDoc=1` | fallback list card price | flag+1 |
| 7b | `Items.PurchPrice` (or `PurchPriceProto`) if `SalesDoc=0` | purchase docs | flag+3 |

**Important:** Special prices run **after** price lists and **override** them when found (`GPFLAG` jumps to ≥50).  
**Important:** Step 3 item promo discount can overwrite matrix discount even after a list price was applied.

### Branch/kupa shortcut (early exit path)

If `GetPrice` rows are for Docs **2/121/137/87** and account = `CompanyDefenitions.InvAcc`, and branch (`AgentWarehouseNames.Sort=6`) has `PriceListID`, GPRICE uses **that branch price list only**, then item defaults, then writes back — **skipping** the full discount/special pipeline in that branch block.

---

## 3. Pricing decision tree (sales document)

```
inputs in GetPrice: StationID, AccountKey, ItemKey, Quantity, DatF, DocumentID
        │
        ▼
Is kupa/branch special case? ──Yes──► Branch PriceListID → Items.Price if needed → done
        │ No
        ▼
Apply Discounts(Account × Item.DiscountCode) → DiscountPrc/Commission
        │
        ▼
Resolve PriceLists via Discounts.PriceListNumber
   where DatF <= quote/doc date; take MAX(DatF)
        │
        ▼
If SalesDoc=1 and Items.DiscountPrc≠0 → replace DiscountPrc with item discount
        │
        ▼
Any SpecialPrices for Account+Item with ValidDate≤DatF≤EndDate and Active=0?
   ├─ MinDebit deal? → GetMinSPrice
   ├─ CalcMethod=0 → highest MinQuantity ≤ qty (GetHighSPrice)
   └─ CalcMethod=1 → split ranges (GetSplitSPrice)
        │
        ▼
Still no price (GPFLAG<20)? → Items.Price (sales) / PurchPrice (purchase)
        │
        ▼
Write PRICE, COIN, DISCOUNTPRC, COMMISIONPRC, GPFLAG back to GetPrice
```

---

## 4. How customer price list is selected

**FACT (GPRICE):** List is not chosen from `Stock.FatherPriceList`.  
It is selected by joining:

`Discounts.AccountKey` (+ optional AssignKey)  
× `Discounts.ItemDiscountCode` = `Items.DiscountCode`  
× `Discounts.PriceListNumber` = `PriceLists.PriceListNumber`

Then the effective list row is the one with `PriceLists.DatF = MAX(DatF)` among rows with `DatF ≤ GetPrice.DatF`.

**Implication:** Without a matching `Discounts` row, the list-price step does not populate price; engine falls through to specials / `Items.Price`.

**Branch exception:** `AgentWarehouseNames.PriceListID` when Sort=6 (warehouse/branch).

---

## 5. Date behavior

| Date field | Role |
|------------|------|
| `GetPrice.DatF` | Pricing-as-of date (IssueDoc loads `@VALUEDATE`) |
| `PriceLists.DatF ≤ DatF` | Effective list version |
| `SpecialPrices.ValidDate ≤ DatF ≤ EndDate` | Special validity window |

**Quotations:** same engine; client/IssueDoc must put quotation value date into `GetPrice.DatF`.  
**FACT:** `DocumentsDef.SalesDoc=1` for Doc 7 → sales path (not purchase).

---

## 6. Quantity / unit / currency / document type

| Factor | Behavior |
|--------|----------|
| Quantity | `ABS(Quantity)`; drives special qty breaks / split |
| Unit | **Not used inside GPRICE** |
| Currency | From PriceLists / SpecialPricesMoves / Items; null → `CompanyDefenitions.MainCurrency` |
| Document type | Via `DocumentsDef.SalesDoc` (sales vs purchase fallback & item discount overlay); kupa docs trigger branch path |
| Customer | `AccountKey`; optional `Accounts.AssignKey` central card; DUMI=1 global specials |

---

## 7. VAT

**FACT:** `GPRICE` does **not** compute VAT.  
It returns unit **price** + **discount %** + currency.  

VAT appears later in document math, e.g. `AddBaseMoves` / issue totals:

`Price * (1 - lineDisc/100) * (1 + (1-VatExempt)*VatPrc/100) * Rate/MainRate * Qty`

Header VAT% from `Stock.VatPrc`; line exempt via `VatExampt`.

---

## 8. Header vs line discounts

| Layer | Where | Formula evidence |
|-------|-------|------------------|
| Line discount | `StockMoves.DiscountPrc` / `GetPrice.DiscountPrc` | Set by GPRICE |
| Header discount | `Stock.DiscountPrc` | **Not set by GPRICE** |
| Combined net (history helper) | `GetAllDocPrices` | `PriceAfter = Price * (1 - line/100) * (1 - header/100)` |
| Combined when basing | `AddBaseMoves` variants | compounds `(1-line)*(1-header)` into amounts; sometimes folds header into line disc `%` |

**Compounding:** sequential multiplicative factors, **not** additive percentages.

Example from `GetAllDocPrices`:

```sql
PriceAfter = StockMoves.Price * (1 - StockMoves.DiscountPrc/100) * (1 - Stock.DiscountPrc/100)
```

---

## 9. Quantity-break behavior

### CalcMethod = 0 (`GetHighSPrice`)

- Pick special header with max `ValidDate` ≤ DatF (and EndDate window in parent query).
- Among moves with `MinQuantity ≤ Quantity` and `Active=0`, take **MAX(MinQuantity)**.
- Apply that move’s `Price`, `CurrencyCode`, `DiscountPrc`.
- Sets `GPFLAG = 50 + @AccType`.

### CalcMethod = 1 (`GetSplitSPrice`)

- Builds quantity bands between successive `MinQuantity` breaks.
- Blends: `SUM(TrueQuant * Price * (1 - DiscountPrc/100)) / Quantity`.
- May insert extra `GetPrice` split rows when `PrintMethod`/ForSplit=1 (`GPFLAG` 60+).

### MinDebit (`GetMinSPrice`)

- When `MinDebit=1` and `Quantity < MinDebitQuant`, forces price from `MinAmount` / qty (floor deal).

**Note:** `Active = 0` means **active** in this codebase (inverted flag).

---

## 10. Minimum-price validation (`CheckMinPrice`)

Separate from resolution:

- Compares line net `Price*Rate*(1-DiscountPrc/100)` to:
  - `Items.PurchPrice` if `CompanyDefenitions.PriceListAlarmID=0`, else
  - latest row of alarm price list `PriceListAlarmID`.
- Leaves only violating rows in `TempMinPrice`.
- Does **not** change `StockMoves` prices.

---

## 11. What GPRICE returns (via `GetPrice` table)

| Output column | Meaning |
|---------------|---------|
| `Price` | Unit price (gross before % discount) |
| `Coin` | Currency code |
| `DiscountPrc` | Line discount **percentage** |
| `CommisionPrc` | Commission % |
| `GPFLAG` | Provenance code |
| `TextInfo` | May carry special item name |

**Not returned:** VAT-inclusive price, header discount, final net extended amount.

Net extended is computed by callers using price × qty × rate × discounts × VAT factors.

---

## 12. When no valid price is found

1. Try specials (account / assign / dumi).  
2. If still `GPFLAG < 20` and sales → `Items.Price`.  
3. Purchase docs → `Items.PurchPrice` / `PurchPriceProto`.  
4. Null discount → 0; null coin → main currency.  

**I don't have enough evidence** whether the UI blocks issue when price remains 0.

---

## 13. Do quotations use the same logic?

**FACT:** Yes for engine — Doc 7 is `SalesDoc=1`; `IssueDoc`/`GPRICE` are document-type agnostic except `SalesDoc` and a few kupa IDs.  
`GetAllDocPrices` explicitly treats Doc **7** as quotation history family (RowNo=4).

Price/discount on conversion is **copied** by `InvCopy*` / `AddBaseMoves` from base lines (not necessarily recalculated), unless a later issue step re-runs GPRICE (observed for TREE=2 sons in `IssueDoc`).

---

## 14. Tables read / modified

| Procedure | Reads | Writes |
|-----------|-------|--------|
| GPRICE | GetPrice, Accounts, Items, DocumentsDef, Discounts, PriceLists, SpecialPrices*, CompanyDefenitions, AgentWarehouseNames, CompanyDefs | GetPrice; temp `#GETPRICE` etc. |
| Get*SPrice | SpecialPrices*, #GETPRICE | #GETPRICE / GetPrice (split) |
| GetAllDocPrices | Stock, StockMoves | TEMPGetAlLPrices |
| CheckMinPrice | Stock, StockMoves, Items, PriceLists, Rates, CompanyDefenitions | TempMinPrice |

---

## 15. Mandatory inputs to reproduce a price

For a sales quote/order line:

1. `StationID`  
2. `AccountKey` (and whether AssignKey / Dumi specials apply)  
3. `ItemKey` (and `Items.DiscountCode`, `Items.Price`, `Items.DiscountPrc`)  
4. `Quantity`  
5. `DatF` (value/quote date)  
6. `DocumentID` (for SalesDoc / kupa branch logic)  
7. Matching `Discounts` / `PriceLists` / `SpecialPrices*` rows as of DatF  
8. `@Split` if split specials needed  

Optional: `BranchID` for branch list path.

---

## 16. GPFLAG cheat sheet (observed)

| Flag | Meaning |
|-----:|---------|
| 0 | unset |
| 10/11 | discount matrix applied (account / assign) |
| 40 | branch price list |
| 41/42 | account/assign price list |
| 50+ | special (High/Min) by AccType 0/1/2 |
| 53+ / 60+ | split special |
| <20 then +1/+3 | item card fallback |

---

## 17. Unresolved pricing questions

1. Does the Windows client set `Stock.FatherPriceList` into pricing before GPRICE, or is it unused legacy?  
2. Exact UI moment GPRICE runs for Doc 7 vs only on issue of TREE sons.  
3. Full meaning of every GPFLAG value.  
4. Whether `AccountDiscountCode` on `Discounts` is used anywhere (not in GPRICE join).  
5. Dynamic SQL: none in GPRICE; `IssueDoc` has later `sp_executesql` unrelated to core list resolution.  
6. `RepriceDoc` / `ConCallPrices` not fully traced in this pass.

---

## 18. Evidence anchors

| Claim | Evidence |
|-------|----------|
| Discounts before lists | `GPRICE` ~L324–336 then ~L390–436 |
| Specials after lists | `exec GetMinSPrice` ~L589; `GetHighSPrice`/`GetSplitSPrice` ~L611–612 |
| Active=0 means active | `GetHighSPrice` WHERE ACTIVE=0 |
| Date effect | `PriceLists.DatF<=#GETPRICE.DATF`; specials Valid/End |
| Quote same SalesDoc path | DocumentsDef SalesDoc for Doc7; GetAllDocPrices RowNo for Doc7 |
| Compound discounts | `GetAllDocPrices` PriceAfter formula |
| IssueDoc calls GPRICE | `EXECUTE GPRICE @STATION_ID,0` ~L632 |
| VAT not in GPRICE | no VatPrc writes in GPRICE outputs |
