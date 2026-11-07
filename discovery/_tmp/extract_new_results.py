import csv
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
import openpyxl

folder = Path(r"C:\Danyor_project\sql server\query results")
out = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp")
out.mkdir(parents=True, exist_ok=True)

files = [
    "tablesID.xlsx",
    "Table_currentMaxID.xlsx",
    "BaseDocs.xlsx",
    "AlterNum.xlsx",
    "Quote lineage through BaseMoveID.xlsx",
    "Operations coverage by table.xlsx",
]

for name in files:
    f = folder / name
    print("\n" + "=" * 80)
    print(name, "exists", f.exists())
    if not f.exists():
        continue
    wb = openpyxl.load_workbook(f, read_only=True, data_only=True)
    for sheet in wb.sheetnames:
        rows = list(wb[sheet].iter_rows(values_only=True))
        print(f"sheet={sheet} rows={len(rows)}")
        for r in rows[:80]:
            print("\t".join("" if c is None else str(c) for c in r))
        if len(rows) > 80:
            print(f"... +{len(rows)-80} more")
        safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in Path(name).stem)[:80]
        with (out / f"{safe}.csv").open("w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerows(rows)
    wb.close()
