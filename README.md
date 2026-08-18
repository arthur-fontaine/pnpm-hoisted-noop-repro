# pnpm 12: `nodeLinker: hoisted` never takes the frozen no-op path in a workspace

A repeat `pnpm install --frozen-lockfile` on an unchanged tree should hit the no-op
short-circuit. With `nodeLinker: hoisted`, and the dependencies declared in a workspace
member rather than the root, pnpm 12 reports all 69 packages in the lockfile broken and
re-imports the whole tree instead, on every install.

## Run

```sh
PNPM=pnpm ./run.sh
```

One workspace member, one dependency (`express@4.21.2`, 69 packages). The script covers four
cases: dependencies in the root or in a member, crossed with `isolated` and `hoisted`.

## Result: pnpm 12.0.0-rc.6, macOS 15.2 arm64, Node 24.16.0

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

Only one of the four cases fails: `hoisted` with the dependencies in a member. `hoisted` with
the dependencies in the workspace root is fine, so the freshness check is not simply unaware
of `hoisted`.

`--frozen-lockfile` is not required. Plain `pnpm install`, repeated on the same tree:

| | plain `pnpm install`, repeated | `--frozen-lockfile`, repeated |
|---|---|---|
| hoisted, deps in member | `Packages: +69`, 69 broken | `Packages: +69`, 69 broken |
| isolated, deps in member | `Already up to date`, 0 broken | `Already up to date`, 0 broken |

## What's wrong

The tree is correct. Under `nodeLinker: hoisted`, `node_modules/.pnpm/` is supposed to hold
nothing but `lock.yaml`, with packages at `node_modules/<name>`. pnpm 10 and pnpm 12 produce
identical trees here.

The freshness probe checks whether `node_modules/.pnpm/<id>/node_modules/<name>` exists. That
path only means something under the isolated layout. Under `hoisted` it is correctly absent,
and pnpm 12 reads that absence as damage:

| | pnpm 10.33.4 | pnpm 12.0.0-rc.6 |
|---|---|---|
| entries in `.pnpm/` | `lock.yaml` | `lock.yaml` |
| `.pnpm/<id>/node_modules` dirs | 0 | 0 |
| `.pnpm/serve-static@1.16.2/node_modules/serve-static` | absent | absent |
| `node_modules/serve-static` | exists | exists |
| repeat `--frozen-lockfile` verdict | `Already up to date` (188 ms) | `Packages: +69` (166 ms) |

`node_modules/.modules.yaml` already records the correct locations, and the probe does not
read it:

```json
"nodeLinker": "hoisted",
"hoistedLocations": { "mime-types@2.1.35": ["node_modules/mime-types"] }
```

That seems to contradict the design described in pnpm/pnpm#13151, which introduced the probe:

> Under GVS/hoisted linker the probe covers the importer links only.

## Version comparison

| pnpm | isolated repeat | hoisted repeat, deps in member |
|---|---|---|
| 10.33.4 | 220 ms | 234 ms, `Already up to date` |
| 11.22.0 | 219 ms | 215 ms, `Already up to date` |
| 12.0.0-rc.6 | 31 ms | 171 ms, re-imports all 69 |

On `isolated`, pnpm 12's short-circuit is about 7x faster than pnpm 10. Under `hoisted` that
gain is lost.

## Why it matters at scale

`hoisted` is not optional for React Native, because Metro cannot resolve pnpm's symlinked
virtual store. It is the documented setup for Expo and React Native monorepos.

On a real 3582-package hoisted monorepo (66 workspace projects, 250k files in
`node_modules`), a repeat `pnpm install --frozen-lockfile` costs:

| pnpm | cold install | repeat install |
|---|---|---|
| 10.33.4 | 32 s | 6 s |
| 11.22.0 | 44 s | 0.5 s |
| 12.0.0-rc.6 | 65 to 78 s | 105 to 138 s |

pnpm 11 answers in half a second, pnpm 12 in about two minutes, re-importing the tree and
emitting one `pnpm:_broken_node_modules` event per package (3582 of them).

The cost tracks file count rather than package count, which is why it is much larger than
this 69-package repro suggests: the repro re-imports 69 packages, the workspace re-imports
250k files.
