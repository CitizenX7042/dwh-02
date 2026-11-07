import sys
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")

import openpyxl

qr = Path(r"C:\Danyor_project\sql server\query results")
out = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp")

for name in ["Triggers.xlsx", "List triggers.xlsx", "operations sample1.xlsx", "operations sample2.xlsx", "Operations sample3.xlsx", "search procedure text.xlsx", "find procedures referencing the critical tables.xlsx", "AccItemsUpdateLog.xlsx"]:
    p = qr / name
    if not p.exists():
        print("missing", name)
        continue
    wb = openpyxl.load_workbook(p, read_only=True, data_only=True)
    print("\n====", name, "sheets", wb.sheetnames)
    for sh in wb.sheetnames:
        ws = wb[sh]
        rows = list(ws.iter_rows(values_only=True))
        print(f"-- sheet {sh} rows={len(rows)}")
        for i, r in enumerate(rows[:40]):
            print(i, r)
        # also dump full CSV for Triggers
        if "Trigger" in name or name.startswith("operations"):
            csv_name = name.replace(".xlsx", ".csv").replace(" ", "_")
            with (out / csv_name).open("w", encoding="utf-8") as f:
                for r in rows:
                    f.write("\t".join("" if c is None else str(c).replace("\n"," ") for c in r) + "\n")
    wb.close()
