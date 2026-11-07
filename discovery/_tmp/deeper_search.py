import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

content = Path(r"C:\Danyor_project\generate_scripts.sql").read_text(encoding="utf-16-le")
if content.startswith("\ufeff"):
    content = content.lstrip("\ufeff")

headers = list(re.finditer(r"/\*{6} Object:\s+(\w+)\s+\[([^\]]+)\]\.\[([^\]]+)\]", content))

def obj_at(pos):
    prev = None
    for h in headers:
        if h.start() > pos:
            break
        prev = h
    return f"{prev.group(1)} {prev.group(3)}" if prev else "?"

# All DocCancel assignments
print("=== DocCancel assignments ===")
for m in re.finditer(r"DocCancel\s*=", content, re.I):
    sn = re.sub(r"\s+", " ", content[max(0,m.start()-120):m.start()+100])
    if "CREATE TABLE" in sn or "[DocCancel]" in sn:
        continue
    print(obj_at(m.start()), "|", sn[:200])

print("\n=== MoveCancel assignments ===")
for m in re.finditer(r"MoveCancel\s*=", content, re.I):
    sn = re.sub(r"\s+", " ", content[max(0,m.start()-120):m.start()+100])
    if "CREATE TABLE" in sn or "[MoveCancel]" in sn:
        continue
    print(obj_at(m.start()), "|", sn[:200])

print("\n=== IDelDoc / soft cancel related ===")
for name in ["IDelDoc", "KB_Cancellation", "ISSUEDOC", "AddBaseMoves", "InvCopy", "ChCredit", "GPRICE"]:
    for h in headers:
        if h.group(2) == name or h.group(3) == name:
            print("found", h.group(1), h.group(3), "at", h.start())

# FatherPriceList anywhere including views
print("\n=== FatherPriceList occurrences (non-table) ===")
n = 0
for m in re.finditer(r"FatherPriceList|SonPriceList", content, re.I):
    o = obj_at(m.start())
    if o.startswith("Table"):
        continue
    sn = re.sub(r"\s+", " ", content[max(0,m.start()-40):m.start()+60])
    print(o, sn[:150])
    n += 1
    if n >= 30:
        break

# ISSUEDOC GPRICE calls
print("\n=== GPRICE callers ===")
for m in re.finditer(r"\bGPRICE\b|\bexec\s+GPRICE|\bEXECUTE\s+GPRICE", content, re.I):
    print(obj_at(m.start()))

# InvUpdateErrorMessage err severity - look at 2nd param meaning in ChCredit
print("\n=== ChCredit extract ===")
for h in headers:
    if h.group(3) == "ChCredit":
        end = next((x.start() for x in headers if x.start() > h.start()), len(content))
        body = content[h.start():end]
        Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp\procs\ChCredit.sql").write_text(body, encoding="utf-8")
        print("wrote ChCredit", len(body))
        # print key lines
        for line in body.splitlines():
            if any(k in line for k in ["res=", "@res", "Obligo", "Credit", "InvUpdate", "return", "SalesDoc", "MaxCredit"]):
                print(line.strip()[:120])
