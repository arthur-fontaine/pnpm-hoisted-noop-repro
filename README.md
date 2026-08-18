# pnpm 12: `nodeLinker: hoisted` never takes the frozen no-op path in a workspace

A repeat `pnpm install --frozen-lockfile` on an unchanged, freshly installed tree should be
a no-op. With `nodeLinker: hoisted` **and the dependencies in a workspace member**, pnpm 12
reports every package broken and re-imports the whole tree, on every install.

## Run

```sh
PNPM=pnpm ./run.sh
```

One workspace member, one dependency (`express@4.21.2`, 69 packages). The script walks a
2x2 — dependencies in the root vs in a member, `isolated` vs `hoisted`.

## Result — pnpm 12.0.0-rc.6, macOS 15.2 arm64, Node 24.16.0

```
pnpm 12.0.0-rc.6
  deps in root, isolated                       36 ms   packages reported broken: 0
  deps in root, hoisted                        31 ms   packages reported broken: 0
  deps in member, isolated                     31 ms   packages reported broken: 0
  deps in member, hoisted  <-- BUG            171 ms   packages reported broken: 69

State of the hoisted tree that was just declared broken:
  entries in node_modules/.pnpm/ : lock.yaml
  .pnpm/<id>/node_modules dirs   : 0
  reported missing               : node_modules/.pnpm/serve-static@1.16.2/node_modules/serve-static
  ...exists?                    : no  (correct: hoisted has no virtual store)
  actually installed at         : node_modules/serve-static (exists)
  .modules.yaml nodeLinker      : hoisted
  .modules.yaml hoistedLocations : mime-types@2.1.35 -> ['node_modules/mime-types']
```

Only one of the four cells is affected: **hoisted + deps in a workspace member.** Hoisted
with the dependencies in the workspace root is fine, so this is not simply "hoisted is
unsupported by the freshness check".

## What's wrong

The tree is correct. `nodeLinker: hoisted` is *supposed* to leave `node_modules/.pnpm/`
holding nothing but `lock.yaml`, with packages at `node_modules/<name>`. pnpm 10 and pnpm 12
produce byte-identical trees here.

The freshness probe asks whether `node_modules/.pnpm/<id>/node_modules/<name>` exists — a
question that only has meaning for the *isolated* layout. Under hoisted the honest answer is
"no, and correctly so", and pnpm 12 reads that as damage:

| | pnpm 10.33.4 | pnpm 12.0.0-rc.6 |
|---|---|---|
| entries in `.pnpm/` | `lock.yaml` | `lock.yaml` |
| `.pnpm/<id>/node_modules` dirs | 0 | 0 |
| `.pnpm/serve-static@1.16.2/node_modules/serve-static` | absent | absent |
| `node_modules/serve-static` | exists | exists |
| repeat `--frozen-lockfile` verdict | `Already up to date` (188 ms) | `Packages: +69` (166 ms) |

`node_modules/.modules.yaml` already records the correct locations and is not consulted:

```json
"nodeLinker": "hoisted",
"hoistedLocations": { "mime-types@2.1.35": ["node_modules/mime-types"] }
```

This also appears to contradict the design stated in pnpm/pnpm#13151, which introduced the
probe: *"Under GVS/hoisted linker the probe covers the importer links only."*

## Version comparison

| pnpm | isolated repeat | hoisted repeat (deps in member) |
|---|---|---|
| 10.33.4 | 220 ms | 234 ms — `Already up to date` |
| 11.22.0 | 219 ms | 215 ms — no re-import |
| 12.0.0-rc.6 | **31 ms** | **171 ms — re-imports all 69** |

pnpm 12's no-op short-circuit is a real ~7x win on `isolated`. Under hoisted it is
forfeited.

## Why it matters at scale

`hoisted` is not optional for React Native: Metro cannot resolve pnpm's symlinked virtual
store, which is why Expo documents `node-linker=hoisted`. On a 3582-package monorepo that
needs it, a repeat `pnpm install --frozen-lockfile` takes **105-138 s** instead of the ~6 s
pnpm 10 takes, emitting one `pnpm:_broken_node_modules` per package (3582 events). The
per-package overhead in this 69-package repro is smaller than that, so a large workspace
likely has an additional factor on top.
