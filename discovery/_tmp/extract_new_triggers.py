import sys
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")
import openpyxl

qr = Path(r"C:\Danyor_project\sql server\query results")
out = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp")

wanted = {
    "DocumentsDef", "JurnalTrans", "JurnalTransMoves",
    "PriceLists", "SpecialPrices", "SpecialPricesMoves", "Discounts",
    "specialprices", "specialpricesmoves",  # case variants
}

for name in ["triggers_definition.xlsx", "trigger_is encrypted.xlsx", "trigger_verify nothing was missed.xlsx"]:
    p = qr / name
    wb = openpyxl.load_workbook(p, read_only=True, data_only=True)
    print("\n====", name, "sheets", wb.sheetnames)
    for sh in wb.sheetnames:
        ws = wb[sh]
        rows = list(ws.iter_rows(values_only=True))
        print(f"-- {sh} rows={len(rows)}")
        if not rows:
            continue
        headers = rows[0]
        print("headers:", headers)
        for i, r in enumerate(rows):
            # print summary for non-definition, full for definitions of interest
            if name.startswith("triggers_definition"):
                # find parent/trigger/def columns
                rowd = dict(zip(headers, r)) if headers else {}
                parent = None
                for k in rowd:
                    if k and "parent" in str(k).lower() or (k and str(k).lower() in ("tablename","table")):
                        parent = rowd[k]
                # fallback positional
                vals = [str(c) if c is not None else "" for c in r]
                joined = " | ".join(vals[:5])
                if i == 0:
                    print("HDR", joined)
                    continue
                # write each trigger to file
                parent_table = None
                trigger_name = None
                definition = None
                # try common layouts
                for idx, h in enumerate(headers):
                    hl = str(h).lower() if h else ""
                    if "parent" in hl and "table" in hl:
                        parent_table = r[idx]
                    elif hl in ("parenttable", "table_name", "tablename"):
                        parent_table = r[idx]
                    elif "trigger" in hl and "name" in hl:
                        trigger_name = r[idx]
                    elif hl in ("triggername", "name"):
                        trigger_name = r[idx]
                    elif "definition" in hl or "definition" in hl or hl in ("triggerdefinition", "definition"):
                        definition = r[idx]
                if parent_table is None and len(r) >= 4:
                    # Schema, Trigger, ParentSchema, ParentTable, Definition?
                    parent_table = r[3] if len(r) > 3 else r[1]
                    trigger_name = r[1] if len(r) > 1 else r[0]
                    definition = r[4] if len(r) > 4 else (r[-1] if r else None)
                print(f"\n--- {trigger_name} on {parent_table} ---")
                print(definition)
                if definition:
                    safe = str(trigger_name).replace("/", "_")
                    (out / f"trig_{safe}.sql").write_text(str(definition), encoding="utf-8")
            else:
                if i < 40:
                    print(i, r)
    wb.close()
