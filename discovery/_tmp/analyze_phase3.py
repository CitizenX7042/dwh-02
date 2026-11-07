import csv
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

tmp = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp")

rows = list(csv.DictReader((tmp / "BaseDocs.csv").open(encoding="utf-8")))
print("BaseDocs rows", len(rows))
keys = {1, 2, 3, 4, 5, 6, 7, 37}
print("\nPairs involving core docs:")
for r in rows:
    b, d = int(r["BaseDocType"]), int(r["DocType"])
    if b in keys and d in keys:
        print(
            f"  base={b} -> doc={d} Purch={r['PurchQuantFlag']} ZeroBase={r['ZeroBaseQuant']} "
            f"UpdSup={r['UpdatFSupplay']} UpdBase={r['UpdatFBase']} Sign={r['QuantSign']} "
            f"CancelBase={r['CancelBaseQnt']} Srt={r['Srt']}"
        )

print("\nLineage:")
for r in csv.DictReader((tmp / "Quote_lineage_through_BaseMoveID.csv").open(encoding="utf-8")):
    print(dict(r))

content = Path(r"C:\Danyor_project\generate_scripts.sql").read_text(encoding="utf-16-le")
if content.startswith("\ufeff"):
    content = content.lstrip("\ufeff")

out = tmp / "procs"
out.mkdir(exist_ok=True)
wanted = {
    "InvIssueDocument",
    "InvIssueDocumentCh",
    "InvChangeStatus",
    "InvReturnStatus",
    "PreAddBaseMoves",
    "RepriceDoc",
    "RePricingUpdate",
    "ChBeforIssue",
    "CheckObligo",
    "InvCheckStock",
}
pat = re.compile(r"/\*{6} Object:\s+StoredProcedure \[([^\]]+)\]\.\[([^\]]+)\]", re.I)
headers = list(pat.finditer(content))
found = set()
for i, h in enumerate(headers):
    name = h.group(2)
    if name not in wanted:
        continue
    end = headers[i + 1].start() if i + 1 < len(headers) else len(content)
    body = content[h.start() : end]
    (out / f"{name}.sql").write_text(body, encoding="utf-8")
    found.add(name)
    print("wrote", name, len(body))
print("missing", wanted - found)

print("\n=== DocCancel UPDATE/SET contexts ===")
n = 0
for m in re.finditer(r".{0,100}DocCancel[A-Za-z]*.{0,120}", content):
    s = re.sub(r"\s+", " ", m.group(0))
    if "CREATE TABLE" in s:
        continue
    if any(k in s.upper() for k in ("UPDATE", "SET ", "INSERT", "DOC CANCEL", "DOCCANCEL")):
        if "AS S" in s and "SELECT" in s.upper():
            continue
        print(s[:220])
        n += 1
        if n >= 40:
            break

print("\n=== FatherPriceList in procedures ===")
# find procedure bodies containing FatherPriceList
for i, h in enumerate(headers):
    end = headers[i + 1].start() if i + 1 < len(headers) else len(content)
    body = content[h.start() : end]
    if re.search(r"FatherPriceList|SonPriceList", body, re.I):
        print("PROC", h.group(2), "mentions Father/SonPriceList")

print("\n=== MoveCancel ===")
for m in re.finditer(r".{0,100}MoveCancel.{0,120}", content, re.I):
    print(re.sub(r"\s+", " ", m.group(0))[:220])

print("\nCREATE TRIGGER in generate_scripts:", len(re.findall(r"CREATE\s+TRIGGER", content, re.I)))
# Try alternate object script
for p in Path(r"C:\Danyor_project").rglob("*.sql"):
    if p.stat().st_size < 1000:
        continue
    # quick binary check for TRIGGER without loading all as utf16 if not
    raw = p.read_bytes()[:4]
    enc = "utf-16-le" if raw[:2] == b"\xff\xfe" else "utf-8"
    try:
        t = p.read_text(encoding=enc, errors="ignore")
    except Exception:
        continue
    c = len(re.findall(r"CREATE\s+TRIGGER", t, re.I))
    if c:
        print(p, "CREATE TRIGGER", c)
