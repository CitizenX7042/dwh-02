# 03 – Relationship Map

**Update:** Document-type nouns now use verified DocumentIDs. No FKs (unchanged).

---

## 1. Core commercial map (verified types)

```
Accounts
  ├── MainAccount≈1  → Customers
  │     Filter = segment (משרד / מוסד / חנות / בי"ס / …)
  │
  └── MainAccount≈2  → Suppliers
        WorF = supplier category (optional)

Customer
  │
  ├── הצעת מחיר (Stock DocumentID=7)
  │     └── StockMoves lines → Items
  │
  ├── הזמנה (6)
  │     └── lines; BaseMoveID chain
  │
  ├── תעודת משלוח (4)
  │     └── lines (inventory out)
  │           │
  │           ├──► חשבונית מס (1)          [primary]
  │           ├──► חשבונית מס/קבלה (2)
  │           └──► חשבונית מס ריכוז (37)  [summary / secondary]
  │
  ├── חשבונית מס זיכוי (3) / החזרה (5)
  │
  ├── קבלה (31) / העברה לבנק (43) / deposits
  │     ├── CashPays / Cheqs / CreditPays
  │     └── ReceiptJurnalMatch → JurnalTrans*
  │
  ├── SpecialPrices / Discounts / AlterKeys
  └── CRMContact (optional)

Supplier
  ├── הזמנת רכש (17) — low volume
  ├── ת.מ.רכש (14)
  └── חשבונית רכש (12)
```

---

## 2. Document chaining (refined)

```
Quote(7) / Order(6) lines
        │
        ├─ InvCopy*  → new doc lines (price copied; no BaseMoveID)
        │
        └─ AddBaseMoves → child lines with BaseMoveID = parent line ID
                │         qty from remaining BaseQuantity
                ▼
         IssueDoc → reduces parent SupplyQuantity / BaseQuantity
                │
                ▼
Delivery(4) → Invoice(1|2|37)
```

**Config:** `BaseDocs` (`PurchQuantFlag`, `UpdatFSupplay`, `UpdatFBase`, `QuantSign`).  
**Summary invoices:** `summinv_issue*` still secondary review.

---

## 3. Pricing relationships (unchanged structure; engine named)

```
GPRICE / GetAllDocPrices / Get*SPrice  (procedures — bodies not yet reviewed)
   ├── PriceListNames ← PriceLists
   ├── SpecialPrices ← SpecialPricesMoves
   ├── Discounts ← DiscountCodes
   └── Items.Price (fallback)
```

Triggers on PriceLists / SpecialPrices / Discounts → likely `Operations` events.

---

## 4. Party model (refined)

```
Accounts
  ├── Customers: MainAccount=1 (BalanceCode often 6)
  ├── Suppliers: MainAccount=2 (BalanceCode often 7)
  └── Other MainAccount values: GL / special — incomplete dictionary
```

`Filter` is **not** the cust/supplier discriminator; it is commercial segment.

---

## 5. CDC / audit relationships (confirmed for Stock*)

```
Stock / StockMoves
        │  triggers Insert/Update/Delete
        │  ※ Update logs OperationType = 'Insert'
        │  ※ skipped when ID > TablesID.LastID
        │  ※ CurrentMax ≫ LastID → recent IDs often unlogged
        ▼
Operations (OperationID = row ID)

DocumentsDef / Jurnal* / PriceLists / SpecialPrices / Discounts
        │  triggers exist (bodies NOT in generate_scripts.sql)
        ▼
Operations (Insert-heavy; pattern assumed similar)

Accounts / Items field edits
        │  (ASSUMPTION: client app — StationId in samples)
        ▼
AccItemsUpdateLog
        │
Zero procedure ──TRUNCATE──► AccItemsUpdateLog (reset only)

BaseDocs (BaseDocType → DocType)
        │  gates AddBaseMoves / IssueDoc open-qty updates
        ▼
StockMoves.BaseMoveID lineage (not InvCopy)
```

See `11_Change_Tracking_Semantics.md`, `12_Operations_Coverage.md`, `13_BaseDocs_Conversion_Matrix.md`.

---

## 6. Minimal entity view

```
Customer
├── Quotations (7)
├── Orders (6)
├── Deliveries (4)
├── Invoices (1,2; rarely 37)
├── Credits/Returns (3,5)
├── Receipts (31,…)
├── Special prices / discounts
└── AlterKeys (sparse)

Item
├── Price lists
├── Alternatives
└── Moves on documents above
```
