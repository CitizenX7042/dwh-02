import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

text = Path(r"C:\Danyor_project\generate_scripts.sql").read_text(encoding="utf-16-le")
if text.startswith("\ufeff"):
    text = text.lstrip("\ufeff")

# Also try schema-only script
schema_path = Path(r"C:\Danyor_project\sql server\generate_scripts_tables_schema_view.sql")
if schema_path.exists():
    schema = schema_path.read_text(encoding="utf-16-le")
    if schema.startswith("\ufeff"):
        schema = schema.lstrip("\ufeff")
else:
    schema = text

out = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp")

wanted = ["DocumentsDef", "Items", "Accounts"]
for name in wanted:
    # Find CREATE TABLE [dbo].[Name]
    pat = re.compile(
        rf"CREATE\s+TABLE\s+\[dbo\]\.\[{name}\]\s*\((.*?)\)\s*ON\s+\[PRIMARY\]",
        re.S | re.I,
    )
    m = pat.search(schema) or pat.search(text)
    if not m:
        # try without ON PRIMARY
        pat2 = re.compile(
            rf"CREATE\s+TABLE\s+\[dbo\]\.\[{name}\]\s*\((.*?)\)\s*GO",
            re.S | re.I,
        )
        m = pat2.search(schema) or pat2.search(text)
    if not m:
        print(f"NOT FOUND: {name}")
        continue
    body = m.group(1)
    (out / f"ddl_{name}.sql").write_text(body, encoding="utf-8")
    print(f"\n==== {name} columns ====")
    # parse column lines
    for line in body.splitlines():
        line = line.strip().rstrip(",")
        if not line or line.startswith("CONSTRAINT") or line.startswith("PRIMARY") or line.startswith("UNIQUE") or line.startswith("CHECK") or line.startswith("FOREIGN"):
            continue
        if line.upper().startswith("ALTER"):
            continue
        # [Col] [type]...
        cm = re.match(r"\[([^\]]+)\]\s+\[([^\]]+)\](.*)", line)
        if cm:
            col, typ, rest = cm.group(1), cm.group(2), cm.group(3)
            # capture precision
            prec = ""
            pm = re.match(r"\(([^)]+)\)", rest.strip())
            if pm:
                prec = f"({pm.group(1)})"
            null = "NULL" if "NULL" in rest.upper() and "NOT NULL" not in rest.upper() else ("NOT NULL" if "NOT NULL" in rest.upper() else "")
            print(f"  {col}|{typ}{prec}|{null}|{line[:120]}")
