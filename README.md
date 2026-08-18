# pnpm 12: `nodeLinker: hoisted` re-imports every package on repeat installs

Install once, then install again with nothing changed. The second install should be a no-op.
Under `nodeLinker: hoisted`, pnpm 12 reports all 69 packages in the lockfile broken and
re-imports the whole tree. pnpm 10 and 11 do not.

Plain `pnpm install`, no `--frozen-lockfile` needed.

## Run

```sh
mise use "npm:pnpm@11"
./run.sh
mise use "npm:pnpm@12.0.0-rc.6"
./run.sh
```

One workspace member, one dependency (`express@4.21.2`, 69 packages).

## Result

pnpm 11.22.0:

```
pnpm 11.22.0
== nodeLinker: isolated
   second install says : Already up to date
   packages reported broken: 0
== nodeLinker: hoisted
   second install says : Already up to date
   packages reported broken: 0
```

pnpm 12.0.0-rc.6:

```
pnpm 12.0.0-rc.6
== nodeLinker: isolated
   second install says : Already up to date
   packages reported broken: 0
== nodeLinker: hoisted
   second install says : Packages: +69
   packages reported broken: 69
   it looked for   : node_modules/.pnpm/qs@6.13.0/node_modules/qs
   which exists?   : no
   package is at   : node_modules/express (exists)
   .pnpm/ contains : lock.yaml
```

pnpm 10.33.4 matches pnpm 11: `Already up to date` under both linkers.

## What's wrong

The tree is correct. Under `nodeLinker: hoisted`, `node_modules/.pnpm/` is supposed to hold
nothing but `lock.yaml`, with packages at `node_modules/<name>`. pnpm 10, 11 and 12 all
produce that same tree.

The freshness probe checks whether `node_modules/.pnpm/<id>/node_modules/<name>` exists. That
path only means something under the isolated layout. Under `hoisted` it is correctly absent,
and pnpm 12 reads that absence as damage.

`node_modules/.modules.yaml` already records where each package went, and the probe does not
read it:

```json
"nodeLinker": "hoisted",
"hoistedLocations": { "qs@6.13.0": ["node_modules/qs"] }
```

This appears to contradict the design described in pnpm/pnpm#13151, which introduced the
probe:

> Under GVS/hoisted linker the probe covers the importer links only.

## One variation worth knowing

The dependency has to be in a workspace member. Move the `dependencies` block from
`member/package.json` into the root `package.json` and set `packages: []`, and pnpm 12 is
fine under `hoisted` too (0 broken). So the check is not simply unaware of `hoisted`.

## Why it matters at scale

`hoisted` is not optional for React Native, because Metro cannot resolve pnpm's symlinked
virtual store. It is the documented setup for Expo and React Native monorepos.

On a 3582-package hoisted monorepo (66 workspace projects, 250k files in `node_modules`), a
repeat install costs:

| pnpm | cold install | repeat install |
|---|---|---|
| 10.33.4 | 32 s | 6 s |
| 11.22.0 | 44 s | 0.5 s |
| 12.0.0-rc.6 | 65 to 78 s | 105 to 138 s |

The cost tracks file count rather than package count, which is why it is far larger than this
69-package repro suggests.
