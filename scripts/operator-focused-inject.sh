set -uo pipefail
printf 'DIAGNOSTIC_READER_SHA '; git rev-parse HEAD
python3 - <<'FIX'
from pathlib import Path
s=Path('scripts/operator-stand-inject.py').read_text()
s=s.replace('cls.run', 'cls.api_run').replace('self.run', 'self.api_run')
s=s.replace('HERE = Path(__file__).resolve().parent', "HERE = Path.cwd() / 'scripts'")
Path('/tmp/operator-stand-harness-fixed.py').write_text(s)
FIX
python3 /tmp/operator-stand-harness-fixed.py; a=$?
printf 'DIAGNOSTIC hosted rc=%s\n' "$a"
python3 scripts/operator-cluster-inject.py "$PWD/scripts/operator-stand.py" "$PWD/scripts/operator-stand-fixtures/cluster-api-shape.json"; b=$?
printf 'DIAGNOSTIC cluster rc=%s\n' "$b"
[ "$a" -eq 0 ] && [ "$b" -eq 0 ]
