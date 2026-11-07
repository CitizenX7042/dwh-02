import re
from pathlib import Path

sys_path = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp")
content = Path(r"C:\Danyor_project\generate_scripts.sql").read_text(encoding="utf-16-le")
if content.startswith("\ufeff"):
    content = content.lstrip("\ufeff")

# Find which object contains the DocCancel UPDATE
idx = content.find("UPDATE Stock SET stock.DocCancel")
print("DocCancel UPDATE at", idx)
# find preceding Object header
headers = list(re.finditer(r"/\*{6} Object:\s+(\w+)\s+\[([^\]]+)\]\.\[([^\]]+)\]", content))
prev = None
for h in headers:
    if h.start() > idx:
        break
    prev = h
if prev:
    print("Object:", prev.group(1), prev.group(2) + "." + prev.group(3), "at", prev.start())
    end = next((h.start() for h in headers if h.start() > prev.start()), len(content))
    body = content[prev.start():end]
    Path(sys_path / "procs" / f"{prev.group(3)}.sql").write_text(body, encoding="utf-8")
    print("wrote", prev.group(3), "len", len(body))

# MoveCancel writers
for m in re.finditer(r"MoveCancel\s*=", content, re.I):
    start = max(0, m.start() - 200)
    snippet = re.sub(r"\s+", " ", content[start:m.start()+80])
    # find object
    prev = None
    for h in headers:
        if h.start() > m.start():
            break
        prev = h
    obj = f"{prev.group(1)} {prev.group(3)}" if prev else "?"
    print("MoveCancel= in", obj, ":", snippet[-180:])

# AccItemsUpdateLog
print("\nAccItemsUpdateLog mentions:")
for m in re.finditer(r"AccItemsUpdateLog", content, re.I):
    prev = None
    for h in headers:
        if h.start() > m.start():
            break
        prev = h
    obj = f"{prev.group(1)} {prev.group(3)}" if prev else "?"
    sn = re.sub(r"\s+", " ", content[max(0,m.start()-60):m.start()+80])
    print(obj, sn)

# TablesID usage
print("\nTablesID writers:")
for m in re.finditer(r"(UPDATE|INSERT\s+INTO)\s+.*TablesID|TablesID.*LastID", content, re.I):
    prev = None
    for h in headers:
        if h.start() > m.start():
            break
        prev = h
    if prev and prev.group(1) == "StoredProcedure":
        sn = re.sub(r"\s+", " ", m.group(0)[:100])
        print(prev.group(3), sn)
