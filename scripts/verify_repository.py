"""Check source scale and prevent private contest materials from being tracked."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
tracked = subprocess.check_output(
    ["git", "-c", "core.quotepath=false", "ls-files", "-z"], cwd=root
).decode().split("\0")
for name in filter(None, tracked):
    parts = Path(name).parts
    forbidden = {"_local", "_build", ".mooncakes", ".venv", "__pycache__"}
    if forbidden.intersection(parts) or any(x in name for x in ["申报书", "审查报告", "辅助报告", "汇总报告"]):
        raise SystemExit(f"Private/generated material is tracked: {name}")

counts = {"library": 0, "tests": 0, "examples": 0, "cli": 0}
for name in filter(None, tracked):
    if not name.endswith(".mbt"):
        continue
    category = "tests" if name.endswith("test.mbt") else (
        "examples" if name.startswith("examples/") else (
            "cli" if name.startswith("cmd/") else "library"
        )
    )
    counts[category] += sum(
        bool(line.strip()) and not line.lstrip().startswith("//")
        for line in (root / name).read_text(encoding="utf-8").splitlines()
    )
total = sum(counts.values())
print({**counts, "total_effective_moonbit_lines": total})
if total <= 4000:
    raise SystemExit("Effective MoonBit source must exceed 4000 lines")
