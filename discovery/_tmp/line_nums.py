import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

path = Path(r"C:\Danyor_project\generate_scripts.sql")
# Count newlines up to positions for citation
raw = path.read_bytes()
# UTF-16 LE: each char 2 bytes, BOM 2 bytes
text = path.read_text(encoding="utf-16-le")
if text.startswith("\ufeff"):
    text = text.lstrip("\ufeff")

# Build line start offsets
lines = text.splitlines(keepends=True)
# Map char offset -> line number
def line_of(pos):
    # binary search on cumulative
    cum = 0
    for i, ln in enumerate(lines, 1):
        cum += len(ln)
        if cum > pos:
            return i
    return len(lines)

headers = list(re.finditer(r"/\*{6} Object:\s+(\w+)\s+\[([^\]]+)\]\.\[([^\]]+)\]", text))

wanted = [
    "InvIssueDocument", "InvIssueDocumentCh", "InvChangeStatus", "InvReturnStatus",
    "PreAddBaseMoves", "RepriceDoc", "RePricingUpdate", "ChBeforIssue", "CheckObligo",
    "InvCheckStock", "KB_Cancellation", "IDelDoc", "AddBaseMoves", "ChCredit",
    "IssueDoc", "GPRICE", "Zero", "ISSUEDOC"
]

print("Object line ranges:")
for i, h in enumerate(headers):
    name = h.group(3)
    if name not in wanted and name.upper() not in {w.upper() for w in wanted}:
        continue
    end = headers[i+1].start() if i+1 < len(headers) else len(text)
    print(f"{h.group(1):16} {name:30} lines {line_of(h.start())}-{line_of(end-1)}")

# DocCancel line
m = re.search(r"UPDATE Stock SET stock\.DocCancel", text)
print("DocCancel UPDATE line", line_of(m.start()) if m else None)

# Search for MoveCancel in any form of write
print("\nMoveCancel non-schema:")
for m in re.finditer(r"MoveCancel", text, re.I):
    o_prev = None
    for h in headers:
        if h.start() > m.start():
            break
        o_prev = h
    kind = o_prev.group(1) if o_prev else "?"
    name = o_prev.group(3) if o_prev else "?"
    if kind == "Table":
        continue
    ctx = text[m.start()-30:m.start()+40].replace("\n"," ")
    if "AS " in ctx and "SELECT" not in text[max(0,m.start()-200):m.start()].upper()[-50:]:
        pass
    print(f"  {kind} {name} L{line_of(m.start())}: {ctx[:80]}")

# AddBaseMoves BaseMoveID / price copy snippets line nums
for pat in [r"BaseMoveID\s*=", r"AlterNum", r"exec.*GPRICE", r"FatherPriceList"]:
    print(f"\npattern {pat}:")
    for h in headers:
        if h.group(3) not in ("AddBaseMoves", "IssueDoc", "InvCopy", "InvCopyDoc"):
            continue
        end = headers[headers.index(h)+1].start() if headers.index(h)+1 < len(headers) else len(text)
        body = text[h.start():end]
        for m in re.finditer(pat, body, re.I):
            print(f"  {h.group(3)} L{line_of(h.start()+m.start())}")
            break
