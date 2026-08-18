#!/bin/sh
# A repeat `pnpm install --frozen-lockfile` on an unchanged tree should be a no-op.
# Under `nodeLinker: hoisted`, when the dependencies live in a workspace member,
# pnpm 12 reports every package broken and re-imports the whole tree, every time.
#
#   PNPM=pnpm ./run.sh          # or PNPM=path/to/pnpm12
set -e
PNPM="${PNPM:-pnpm}"
echo "pnpm $($PNPM --version)"

case_run() {                       # $1 = label, $2 = packages: value, $3 = linker
  printf 'packages: %s\nnodeLinker: %s\n' "$2" "$3" > pnpm-workspace.yaml
  rm -rf node_modules member/node_modules
  $PNPM install --lockfile-only >/dev/null 2>&1
  $PNPM install --frozen-lockfile >/dev/null 2>&1     # populate; tree is now correct
  s=$(python3 -c 'import time;print(time.time())')
  $PNPM install --frozen-lockfile --reporter=ndjson 2>ndjson.log >/dev/null
  e=$(python3 -c 'import time;print(time.time())')
  b=$(grep -c '_broken_node_modules' ndjson.log || true)
  python3 -c "print(f'  {'$1':<40} {($e-$s)*1000:6.0f} ms   packages reported broken: $b')"
}

# deps in the workspace ROOT — no member project
mv member/package.json ./member-package.json.bak
python3 - <<'PY'
import json
m=json.load(open('member-package.json.bak')); r=json.load(open('package.json'))
r['dependencies']=m['dependencies']; json.dump(r,open('package.json','w'),indent=2)
PY
case_run "deps in root, isolated" "[]" isolated
case_run "deps in root, hoisted" "[]" hoisted
python3 - <<'PY'
import json
r=json.load(open('package.json')); r.pop('dependencies',None); json.dump(r,open('package.json','w'),indent=2)
PY
mv ./member-package.json.bak member/package.json

# deps in a workspace MEMBER
case_run "deps in member, isolated" "[member]" isolated
case_run "deps in member, hoisted  <-- BUG" "[member]" hoisted

echo
echo "State of the hoisted tree that was just declared broken:"
echo "  entries in node_modules/.pnpm/ : $(ls -A node_modules/.pnpm 2>/dev/null | tr '\n' ' ')"
echo "  .pnpm/<id>/node_modules dirs   : $(find node_modules/.pnpm -maxdepth 2 -name node_modules -type d 2>/dev/null | wc -l | tr -d ' ')"
python3 - <<'PY'
import json,os
miss=None
for l in open('ndjson.log',errors='ignore'):
    if '_broken_node_modules' in l:
        miss=json.loads(l.strip())['missing']; break
if miss:
    rel=os.path.relpath(miss, os.getcwd())
    print("  reported missing               :", rel)
    print("  ...exists?                    :", "yes" if os.path.exists(miss) else "no  (correct: hoisted has no virtual store)")
    name=rel.rsplit('/node_modules/',1)[-1]
    print(f"  actually installed at         : node_modules/{name}",
          "(exists)" if os.path.exists(f"node_modules/{name}") else "(MISSING)")
m=json.load(open('node_modules/.modules.yaml'))
print("  .modules.yaml nodeLinker      :", m.get('nodeLinker'))
hl=m.get('hoistedLocations') or {}
k=next((x for x in hl if x.startswith('mime-types')), next(iter(hl), None))
if k: print(f"  .modules.yaml hoistedLocations : {k} -> {hl[k]}")
PY
