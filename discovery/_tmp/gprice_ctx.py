import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
text = Path(r"C:\Danyor_project\generate_scripts.sql").read_text(encoding="utf-16-le")
if text.startswith("\ufeff"):
    text = text.lstrip("\ufeff")

m = re.search(
    r"Object:\s+StoredProcedure \[dbo\]\.\[AddBaseMoves\].*?(?=/\*{6} Object:)",
    text,
    re.S | re.I,
)
body = m.group(0)
out = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp\procs\AddBaseMoves.sql")
out.write_text(body, encoding="utf-8")
print("len", len(body))
for gm in re.finditer(r"GPRICE", body, re.I):
    start = max(0, gm.start() - 600)
    end = min(len(body), gm.end() + 250)
    snippet = body[start:end]
    Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp\addbasemoves_gprice.txt").write_text(
        snippet, encoding="utf-8"
    )
    print("wrote snippet around", gm.start())
    print(re.sub(r"\s+", " ", snippet)[:500])
