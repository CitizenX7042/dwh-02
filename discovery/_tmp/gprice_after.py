import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
body = Path(r"C:\Users\dexon\Repo\dwh-02\discovery\_tmp\procs\AddBaseMoves.sql").read_text(encoding="utf-8")
pos = body.upper().find("EXECUTE GPRICE")
# after GPRICE - next 2500 chars
print(re.sub(r"\s+", " ", body[pos : pos + 2500]))
