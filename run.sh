#!/bin/sh
# Install once, then install again with nothing changed. The second install should be
# a no-op. Under nodeLinker=hoisted, pnpm 12 re-imports every package instead.
set -e
PNPM="${PNPM:-pnpm}"
echo "pnpm $($PNPM --version)"

for LINKER in isolated hoisted; do
  printf 'packages:\n  - member\nnodeLinker: %s\n' "$LINKER" > pnpm-workspace.yaml
  rm -rf node_modules member/node_modules
  $PNPM install >/dev/null 2>&1                       # first install
  $PNPM install --reporter=ndjson 2>ndjson.log >/dev/null   # second install, nothing changed

  echo "== nodeLinker: $LINKER"
  echo "   second install says : $($PNPM install 2>&1 | grep -E 'Already up to date|^Packages:' || echo '(nothing)')"
  echo "   packages reported broken: $(grep -c _broken_node_modules ndjson.log || true)"

  MISS=$(grep -o '"missing":"[^"]*"' ndjson.log | head -1 | sed 's/"missing":"//; s/"$//')
  if [ -n "$MISS" ]; then
    echo "   it looked for   : ${MISS#$PWD/}"
    echo "   which exists?   : $( [ -e "$MISS" ] && echo yes || echo no )"
    echo "   package is at   : node_modules/express $( [ -e node_modules/express ] && echo '(exists)' )"
    echo "   .pnpm/ contains : $(ls -A node_modules/.pnpm | tr '\n' ' ')"
  fi
done
