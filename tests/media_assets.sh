#!/usr/bin/env bash
set -euo pipefail

for name in normal ide zen settings ai extensions git terminal diagnostics completion; do
    test -s "docs/media/$name.svg"
    test -s "docs/media/$name.cast"
    test -s "docs/media/$name.txt"
    grep -Fq '<svg ' "docs/media/$name.svg"
    python3 - "$name" <<'PY'
import json, pathlib, sys
lines = pathlib.Path(f"docs/media/{sys.argv[1]}.cast").read_text(encoding="utf-8").splitlines()
assert json.loads(lines[0])["version"] == 2
assert json.loads(lines[1])[1] == "o"
PY
done

grep -Fq 'NORMAL' docs/media/normal.txt
grep -Fq 'IDE' docs/media/ide.txt
grep -Fq 'ZEN' docs/media/zen.txt
grep -Fq 'Tuim Settings' docs/media/settings.txt
grep -Fq 'SOURCE CONTROL' docs/media/git.txt
grep -Fq 'TERMINAL' docs/media/terminal.txt
grep -Fq 'EXTENSION SHOP' docs/media/extensions.txt
grep -Fq 'Explore: All Plugins' docs/media/extensions.txt
grep -Fq 'demo.lua' docs/media/diagnostics.txt
grep -Fq 'demo.lua' docs/media/completion.txt
grep -Fq 'W:1' docs/media/diagnostics.txt
grep -Fq '󰻾 and' docs/media/completion.txt
if grep -Eq 'stack traceback|Press ENTER|Cannot make changes' docs/media/*.txt; then
    echo "Generated media contains a startup or editing error" >&2
    exit 1
fi

echo "Generated media assets validated"
