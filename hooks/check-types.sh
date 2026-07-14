#!/bin/sh
# PostToolUse hook (Edit|Write|MultiEdit) — after a .ts/.tsx edit, typecheck
# only the package containing the file (nearest tsconfig.json, local tsc).
# Exit 2 + stderr feeds the errors back to Claude immediately instead of at build time.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT=$(cat)
export BH_HOOK_INPUT="$INPUT"

FILE=$(printf '%s' "$INPUT" | python3 -c \
  "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" \
  2>/dev/null)

case "$FILE" in
  *.ts|*.tsx|*.mts|*.cts) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

# Nearest tsconfig.json above the file
TSCONFIG_DIR=""
DIR=$(dirname "$FILE")
while [ -n "$DIR" ] && [ "$DIR" != "/" ]; do
  if [ -f "$DIR/tsconfig.json" ]; then
    TSCONFIG_DIR="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done
[ -n "$TSCONFIG_DIR" ] || exit 0

# Nearest local tsc at or above the tsconfig (monorepo root hoisting)
TSC=""
DIR="$TSCONFIG_DIR"
while [ -n "$DIR" ] && [ "$DIR" != "/" ]; do
  if [ -x "$DIR/node_modules/.bin/tsc" ]; then
    TSC="$DIR/node_modules/.bin/tsc"
    break
  fi
  DIR=$(dirname "$DIR")
done
[ -n "$TSC" ] || exit 0

if OUT=$("$TSC" --noEmit -p "$TSCONFIG_DIR/tsconfig.json" 2>&1); then
  python3 "$HOOK_DIR/_metric.py" check-types \
    '{"result":"clean","error_count":0,"is_burst":false}' 2>/dev/null || true
  exit 0
fi

N=$(printf '%s\n' "$OUT" | grep -c "error TS" 2>/dev/null || echo 1)
[ "$N" -ge 1 ] 2>/dev/null || N=1
BURST=false
[ "$N" -ge 10 ] && BURST=true
python3 "$HOOK_DIR/_metric.py" check-types \
  "{\"result\":\"errors\",\"error_count\":$N,\"is_burst\":$BURST}" 2>/dev/null || true

{
  echo "tsc found type errors in $TSCONFIG_DIR after editing $FILE — fix them now:"
  printf '%s\n' "$OUT" | head -40
} >&2
exit 2
