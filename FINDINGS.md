# Two open test failures, and exactly what each one is

State at `0a29e4df` + the FS-540 fix: `110 -> 111 PASS, 1 SKIP, 2 FAIL`.

Both remaining failures are real defects in this repository, not flakes, and
neither is "pre-existing". They are recorded here with the measurement that
locates each one, because guessing at them has already cost two attempts and
one revert (`d7c96ba0` / `991048f4`).

## `tests/FS-310-HDS-020-SDS-010-SMS-060.sh` — one authority, several primitives

The test groups rendered policy routes by `(container, family, table, prefix,
metric)` and fails when two different interfaces claim one group.

### What the model says

`network-control-plane-model` publishes `canonicalRoutes`, one entry per
`(target, interface, family, table, destination, gateway, metric)`. For the
`wireguard-provider-overlay` example:

```
s-router-upstream-selector, 100.64.0.0/24
  ens6  table 1005  gateway 10.10.0.6     <- declared
  ens5  table 1004  gateway 10.10.0.16    policyOnly
  ens10 table 1001  gateway 10.10.0.18    policyOnly
```

One authority, three interfaces, three DIFFERENT tables. That is legitimate
multipath/scoping in the model.

### What the renderer renders

The renderer installs those three entries in EVERY policy table of the node:

```
s-router-upstream-selector
  10-ens5  100.64.0.0/24  t=1001 m=40, t=1001 m=50, t=1004 ..., t=1005 ...
  10-ens10 100.64.0.0/24  t=1001 ..., t=1004 ..., t=1005 ...
```

So one canonical record becomes up to six primitives. `ip route replace` keys
on `(family, table, destination, metric)`, so which one survives is decided by
installation order.

### Where the widening happens

`policy-routing/aggregate.nix`, `tableForOutputIfName`: for a `policy` or
`upstream-selector` node it answered `tableId` (the table of the interface being
iterated) for EVERY output interface, and
`policy-routing/routes-by-output-interface.nix` applies the answer as the
route's table. Changing it to the output interface's own allocation stops the
table widening but leaves duplicates where two interfaces share one table.

### The measurement that makes this exact

For `s-router-policy` and the prefix `100.64.0.2/32`, the model declares FIVE
records, each on its own link in its own table:

```
ens6  table 1004  gateway 10.10.0.10
ens5  table 1003  gateway 10.10.0.12
ens7  table 1005  gateway 10.10.0.14
ens4  table 1002  gateway 10.10.0.17
ens9  table 1006  gateway 10.10.0.19
```

The renderer emits that prefix THREE times in table 1005 alone (and again in
1004, 1002, ...). So the disagreement is not a tie to break: every canonical
record has a unique `(runtimeIfName, tableId)` home, and the renderer is
installing one record's route in every policy table of the node.

That is why every "merge the duplicates" approach fails -- there are no
duplicates in the model. There are extra copies in the renderer.

Rendered per interface (`s-router-policy`, same prefix), which shows the shape
of the broadcast and not just its size:

```
10-ens4  t=1002 t=1002 t=1004 t=1004 t=1006                       (5)
10-ens5  t=1001 t=1001 t=1003 t=1003 t=1004 t=1005                (6)
10-ens6  t=1002 t=1002 t=1003 t=1004 t=1004 t=1005 t=1006 t=1006  (8)
10-ens7  t=1003 t=1004 t=1005                                     (3)
10-ens9  t=1002 t=1004 t=1004 t=1006 t=1006                       (5)
```

29 rendered copies for 5 canonical records. Note the pairs: `t=1002 t=1002` on
one interface is the same route installed twice in the same table, and
`t=1004` appears on all five interfaces though the model names it on ens6 only.

So the defect has two parts, and both have to go:

1. a record's route is installed on interfaces that do not declare it;
2. some records are installed twice in the same table on the same interface.

Part (2) is why the `policyOnly`-keyed dedupe in the CPM was worth fixing
(`11ad3ac`) — the model no longer contributes it — but the renderer still
produces both kinds on its own.

### The number that makes the fix unambiguous

`s-router-policy` in `wireguard-provider-overlay`:

| | routes |
| --- | --- |
| canonicalRoutes for that target | **97** |
| rendered across its 6 interfaces | **427** |

and the canonical 97 have exactly one home each:

```
ens3/1001  ens4/1002  ens5/1003  ens6/1004  ens7/1005  ens9/1006
```

Six `(runtimeIfName, tableId)` pairs, one table per interface, no overlaps. The
mapping is therefore 1:1 and already complete: every rendered route that is not
one of those 97 is invented by the renderer.

That also removes the worry that motivated the failed attempts. There is no
ambiguity to resolve, no owner to elect, no order to preserve — just "install
this record on this interface in this table", which is what
`canonicalRoutes` already says.

### What does NOT work, and why

- Dropping duplicates by iteration order (`d7c96ba0`) deletes the declaring
  interface's route and keeps the copy. `test-upstream-selector-core-main-routes`
  and `test-transit-endpoint-return-routes` assert exactly those routes
  (`10.90.10.0/24` via `10.80.0.16` in table 1001 on `10-core`) and go red.
- Re-homing every copy onto one "owner" interface is the same mistake with a
  different rule: a route that exists in table T on link A is not preserved by
  putting it in table T on link B.
- Keying the dedupe on `policyOnly` keeps both copies alive (the two entries
  differ only there) — that was the original CPM defect, fixed in `11ad3ac`.

### The shape of the real fix

The renderer must install each canonical route in exactly the
`(runtimeIfName, tableId)` the canonical record names, and it must not add a
second interface's copy. That needs `canonicalRoutes` to reach the renderer, and
the policy-routing derivation (`tableForRoute`, `extraTableForRoute`,
`rawRoutesForPolicyTable`) replaced by a mapping of the canonical record. The
mechanism is not a dedupe pass; it is removing the derivation.

## `tests/test-raw-cpm-consumption.sh` — the raw-CPM gate

16 implementation files still read the plain control-plane model:

```
flake.nix
s88/ControlModule/api/debug-payload.nix
s88/ControlModule/firewall/lookup/communication-contract.nix
s88/ControlModule/module/dns-validation-authority.nix
s88/ControlModule/module/public-ingress/facts.nix
s88/ControlModule/render/dry-config-model/sites.nix
s88/ControlModule/render/host-management.nix
s88/ControlModule/render/model-contract-diagnostics.nix
s88/EquipmentModule/mapping/wan-attachment/lookup.nix
s88/Unit/api/host-build/runtime-targets.nix
s88/Unit/lookup/host-runtime/context.nix
s88/Unit/lookup/runtime-context/base/common.nix
s88/Unit/lookup/runtime-context/base/realization.nix
s88/Unit/mapping/runtime-targets/forwarding.nix
s88/Unit/physical/realization-ports/source-model.nix
s88/Unit/render/host-network.nix
s88/Unit/render/host-plan/default.nix
```

`flake.nix` builds `controlPlaneOut` from `validated.controlPlaneEnvelope` and
every s88 module reads `controlPlaneOut.control_plane_model.{data,forwardingModel,realization}`.

`bundle.canonical` now exists (network-realization-model `d9a1f54`), but it
carries interfaces, routes, sites, runtime targets and WireGuard only. These
modules read two things it does not publish:

- `control_plane_model.forwardingModel` — the forwarding model's relations;
- `control_plane_model.realization[.nodes]` — realization node facts
  (deployment hosts, runtime context).

So this is not a refactor of the renderer alone. It needs the producer to
publish those as canonical collections (`canonicalForwarding`,
`canonicalRealization` or equivalent) and the schema to name them, which is a
URS/FS-level contract change and the repository rules require human review for
those. Filed here rather than worked around: a fallback to the model would
restore exactly the dependency the gate exists to remove.

## The duplication masks a second, independent defect

Found while attempting the fix that this file describes (attempt three, reverted
like the first two). De-duplicating by "keep only the copy whose table is this
interface's own allocation" made
`FS-310-HDS-020-SDS-010-SMS-060` pass -- 740 routes, no duplicate occurrence --
and simultaneously removed a route the model DOES declare:

```
model, target esp0xdeadbeef-site-c-c-router-upstream-selector, interface core,
table 1001:
  0.0.0.0/0                  gw 10.80.0.4
  10.80.0.4/31               connected
  10.89.0.2/32               gw 10.80.0.4
  10.90.10.0/24              gw 10.80.0.18
  10.90.20.0/24              gw 10.80.0.14
  ::/0                       gw fd42:dead:cafe:1000:0:0:0:4
  fd42:dead:cafe:0010::/64   gw fd42:dead:cafe:1000:0:0:0:12
  fd42:dead:cafe:1000::4/127 connected
  fd42:dead:cafe:1900::2/128 gw fd42:dead:cafe:1000:0:0:0:4

after that de-duplication, the rendered 10-core (table 1001) carried only:
  0.0.0.0/0, 10.89.0.2/32, ::/0, fd42:dead:cafe:1900::2/128
```

So the renderer does not put `10.90.10.0/24` in table 1001 for `core` at all --
it puts it somewhere else, and the duplicated copies were what made
`test-upstream-selector-core-main-routes` see it. The two defects are
independent:

1. **duplication** -- one authority installed several times (the 97 vs 427
   measurement above);
2. **table assignment** -- a route installed in a table other than the one the
   canonical record names (`10.90.10.0/24` on `core` is table 1001 in the model
   and not there after de-duplication).

Neither can be fixed alone. De-duplicating alone unmasks (2) and the core
return-route contracts go red; fixing table assignment alone leaves (1). A
correct change must install each canonical route on exactly the
`(runtimeIfName, tableId)` it names -- which handles both at once, and is why
the fix is "map canonicalRoutes", not "dedupe" or "retable".

Also worth recording: `test-upstream-selector-core-main-routes` asserted
`10.90.10.0/24` via `10.80.0.16` and a `10.80.0.2/31` on `core`. The model says
`10.80.0.18` and does not declare `10.80.0.2/31` on `core` at all. The test
passed because the renderer invented copies, so it agreed with the bug it was
meant to constrain. Correcting it is part of the fix, not a separate cosmetic
change -- and doing it before the renderer is fixed would just make the test
wrong in a different direction.

## Fourth attempt: the stamping site is not the installation site

Attempt four, also reverted. It changed `raw-routes.nix` to stamp each route
with its SOURCE interface's allocation instead of the iterating interface's:

```nix
sourceTableId =
  let allocation = policyRoutingAllocations.${sourceIfName} or null; in
  if builtins.isAttrs allocation then allocation.tableId or tableId else tableId;
```

That is where the route RECORD is built, and it is not where the route is
INSTALLED. `tableForOutputIfName` and `tableForRoute` in `aggregate.nix`
override the stamped value before anything is rendered, so the change had no
effect on the emitted tables -- verified by rendering `10-core` afterwards and
finding `10.90.10.0/24` still absent from it.

What it DID do was make `test-upstream-selector-core-main-routes` pass. That is
a false green: the test asks `tableForInterface "core"`, which resolves to
table 1001 and then searches EVERY interface's routes for that table, so it
found the copy on `10-pol-dmz-ew` (table 1001, gateway 10.80.0.16) instead of
the route the model declares on `core` (table 1001, gateway 10.80.0.18). The
test cannot tell "core has this route" from "some interface has this route in
core's table".

Two things to fix, and the second is why four attempts have now failed:

1. the installation path (`tableForOutputIfName`, `tableForRoute`,
   `extraTableForRoute`, and the per-output accumulation in `aggregate.nix`),
   not the record-building path in `raw-routes.nix`;
2. `test-upstream-selector-core-main-routes` must assert the route is on the
   interface it names, not that it exists somewhere in that interface's table.
   As written it cannot fail when `core` loses its routes, which is exactly the
   condition it exists to detect.

## Root cause, finally: `routeOutputInterface` relocates a route by peer address

Six attempts narrowed it to the installation path; this names the function.

`policy-routing/route-helpers.nix`:

```nix
routeOutputInterface =
  sourceIfName: route:
  let
    gateway = routeGateway route;
    matchingInterfaces =
      lib.filter
        (ifName: interfacePeerForFamily gateway.family interfaces.${ifName} == gateway.gateway)
        interfaceNames;
  in
  if gateway == null || sourceInterfacePeer == gateway.gateway || matchingInterfaces == [ ] then
    sourceIfName
  else
    builtins.head matchingInterfaces;
```

A route is MOVED from the interface that declares it to whichever interface has
`gateway` as its p2p peer address. Measured on
`s-router-overlay-dns-lane-policy`, target `c-router-upstream-selector`:

```
core             addr4 10.80.0.5/31   -> peer 10.80.0.4
pol-dmz-ew       addr4 10.80.0.17/31  -> peer 10.80.0.16
policy-dmz-wan   addr4 10.80.0.19/31  -> peer 10.80.0.18
```

The model declares `10.90.10.0/24` on `core` in table 1001 with gateway
`10.80.0.18`. `10.80.0.18` is `policy-dmz-wan`'s peer, so the route is
installed on `policy-dmz-wan` and `core` keeps nothing. That is why:

- `10-core` has no `10.90.10.0/24`, however the table is chosen;
- the rendered set carries copies on `10-pol-*` interfaces;
- and `test-upstream-selector-core-main-routes` passes: it searches every
  interface for table 1001 and finds the relocated copy.

This is precisely what FS-310-HDS-020-SDS-010-SMS-060 forbids, in its own words:

> "The renderer shall not choose, infer, or withhold a route's table or lane
>  occurrence: it shall not gate a route's materialization on the presence of a
>  forwarding rule, **derive occurrence from interface topology**, or rely on an
>  environment-supplied fallback table."

`routeOutputInterface` IS "derive occurrence from interface topology". That is
the defect. Not the dedupe, not the table choice, not the stamping site.

Fixing it means the route is installed on the interface the canonical record
names, and `matchingInterfaces` disappears from the materialization path. It is
also why five earlier attempts failed: each of them worked downstream of this
function, on a set that had already been relocated.

Caveat before changing it: `routeOutputInterface` is called from 6 places in
`raw-routes.nix` and is also used for the return-route and lane scoping paths.
Removing it is not a one-line change, and the first thing to do is make
`test-upstream-selector-core-main-routes` assert per-interface so the change can
be validated at all.

## The producer half: `policyRoutingSources` is never published

The last piece, and it explains why every renderer-side attempt failed.

`policy-routing/source-interfaces.nix` prefers model data when it exists:

```nix
forTarget = targetName:
  let unitSources = policyRoutingSources.${targetName} or null;
  in
  if unitSources != null then lib.unique (unitSources ++ ...)
  else lib.unique (selfSources ++ acceptedForwardSources ++ acceptedForwardTargets ++ serviceDnsForwardTargets);
```

That `policyRoutingSources` value comes from
`runtimeTarget.policyRoutingSources` via
`mapping/container-runtime/model/container-assembly.nix`. Measured for
`esp0xdeadbeef-site-c-c-router-upstream-selector` -- the target whose routes this
whole investigation is about:

```
keys: advertisements effectiveRuntimeRealization egressIntent forwardingFunctions
      forwardingIntent forwardingResponsibility logicalNode placement role
      routingAuthority routingMode services stateContracts traversalParticipation
policyRoutingSources: ABSENT
```

So `forTarget` takes the `else` branch: `selfSources ++ acceptedForwardSources
++ acceptedForwardTargets ++ serviceDnsForwardTargets`, all of which the
renderer derives from topology. Combined with `routeOutputInterface` above,
that is the complete mechanism: the renderer decides which lanes carry a
route and which interface installs it, from link topology, because the model
never says.

### What that means for the fix

It is not a renderer patch. Two producer-side facts are missing:

1. `runtimeTarget.policyRoutingSources` -- per target, which source interfaces
   feed which policy table. With it, `forTarget` stops guessing.
2. the canonical route record already carries `(runtimeIfName, tableId)` per
   route (the 97-vs-427 measurement); the renderer should install exactly those
   and nothing else, which removes the need for `routeOutputInterface` in the
   materialization path entirely.

Until (1) exists, "install the route on the interface the model names" cannot
be expressed: the model does not name a source set. That is why six renderer
attempts failed, and it is a producer change, not a renderer one.

## The source of every source set: a renderer-invented topology rule table

`s88/Unit/mapping/runtime-targets/interfaces/policy-routing-sources.nix` computes
`policyRoutingSources` from scratch, for every target, out of interface CLASS and
LANE TOPOLOGY:

```nix
sourcesFor = target:
  if isSelector && hasClass "edgeFacing" target then
    lib.filter (name: hasClass "fabricFacing" name && sameAccess target name) names
  else if isUpstreamSelector && hasClass "coreFacing" target then
    lib.unique ([ target ] ++ lib.filter (name: hasClass "exitFacing" name && sameUplink target name) names)
  else if isPolicy && hasClass "fabricFacing" target then
    lib.filter (name: hasClass "fabricFacing" name || (hasClass "exitFacing" name && sameAccess target name)) names
  ...
```

with helpers `hasClass`, `sameAccess` (equal `backingRef.lane.access`) and
`sameUplink` (shared `backingRef.uplinks`). Nothing here is model output -- the
CPM publishes no `policyRoutingSources` at all (verified: the string appears
nowhere in `network-control-plane-model/src`), so this function is the sole
author of every source set, and therefore of every route occurrence.

FS-310-HDS-020-SDS-010-SMS-060, verbatim:

> "Install each canonical route into exactly the context table and lane the
>  canonical record names. The renderer shall not choose, infer, or withhold a
>  route's table or lane occurrence: it shall not gate a route's materialization
>  on the presence of a forwarding rule, derive occurrence from interface
>  topology, or rely on an environment-supplied fallback table."

This file is a rule table that derives lane occurrence from interface topology.
Together with `routeOutputInterface` (which relocates an individual route by
peer address) it accounts for every symptom in this document: the duplicates,
the missing routes on the declaring interface, and the tests that passed because
copies elsewhere satisfied them.

### The whole picture, in three lines

1. `policy-routing-sources.nix` decides, from class/lane/uplink topology, which
   interfaces feed which policy table.
2. `routeOutputInterface` moves each route to the interface whose p2p peer
   equals the route's gateway.
3. `canonicalRoutes` already states both answers per route
   (`runtimeIfName`, `tableId`) and is ignored.

A correct renderer maps (3) and deletes (1) and (2) from the materialization
path. That is a rewrite of the policy-routing layer, not a patch, which is why
six focused attempts all failed and why each one produced either a regression or
a false green.

## Attempt seven: the relocation is not purely wrong, which narrows the fix

Reverted, but it produced the last missing fact.

Making `routeOutputInterface` return its source interface (`sourceIfName`) made
`test-upstream-selector-core-main-routes` pass LEGITIMATELY -- that test now
asserts per-interface, so a pass means `core` really carries its routes. It also
broke `FS-540-HDS-010-SDS-010-SMS-040`, which requires

```
::/0 gw fd42:dead:feed:1000:0:0:0:4
```

on `pol-hostile-ew` table 1004 -- and the model DOES declare exactly that there:

```
espbranch-site-b-b-router-upstream-selector
  core-nebula       t=1002  ::/0  gw fd42:dead:feed:1000:0:0:0:4
  core-isp          t=1001  ::/0  gw fd42:dead:feed:1000:0:0:0:6
  pol-branch-ew     t=1003  ::/0  gw fd42:dead:feed:1000:0:0:0:4  (and :6, :c)
  policy-branch     t=1005  ::/0  gw fd42:dead:feed:1000:0:0:0:4 / :6
  pol-hostile-ew    t=1004  ::/0  gw fd42:dead:feed:1000:0:0:0:4 / :10 / :c
```

So the same prefix is modelled on five interfaces in five different tables, and
each must be installed where the model says. `routeOutputInterface` is used both
to place those correctly AND to relocate routes that should have stayed put --
one function doing a legitimate job and an illegitimate one, which is why
neither removing it nor keeping it passes.

### The model itself is nearly clean

Same target, measured:

| | count |
| --- | --- |
| canonicalRoutes for `b-router-upstream-selector` | **104** |
| distinct `(interface, table, dst, gateway)` among them | **102** |

Only 2 duplicates in the model (worth a separate look, but tiny). Against
`s-router-policy`'s 97 canonical vs 427 rendered, that establishes the ratio:
**the model is essentially clean and the renderer inflates by roughly 4x.**

### What this means

The fix cannot be a change to `routeOutputInterface`'s return value, and cannot
be a dedupe. It has to install each canonical route at exactly its
`(runtimeIfName, tableId)` -- which means `rawRoutesForPolicyTable` must be
replaced by a mapping from `canonicalRoutes`, and `routeOutputInterface`,
`policy-routing-sources.nix`, `tableForOutputIfName`, `tableForRoute` and
`extraTableForRoute` all leave the materialization path. Seven attempts have now
established that from seven directions.

## Attempt eight: threading canonicalRoutes through the render is a silent no-op

Reverted. Worth recording because it looked like the fix and did nothing.

The plan was a narrow one: filter at final assembly
(`render/container-networks/interface-units.nix`) so a policy-table route the
canonical set does not declare on this interface/table is dropped. The predicate
was added, and the value threaded:

```
flake.nix  (canonical.hostModule)     -> cpm = validated.controlPlaneEnvelope
render/containers.nix                 -> canonicalRoutes from cpm.control_plane_model
render/containers/default.nix         -> inputs.nix
render/containers/inputs.nix          -> returned in the inputs attrset
render/containers/emission.nix        -> module.nix
render/containers/module.nix          -> container-networks.nix
render/container-networks.nix         -> interface-units.nix
```

Every file parses, the suite runs, and the filter matches NOTHING. Verified two
ways: with the predicate relaxed to `(interface, dst)` -- still nothing -- and
with a `builtins.trace` on the list length, which never printed.

So one of those six hops drops the value, and `canonicalRoutes ? [ ]` makes every
hop silently succeed at doing nothing. That is the same failure shape as the
whole defect: a default that turns "I have no data" into "there is nothing to
check".

This is why the fix has to be a rewrite in which `canonicalRoutes` is not an
optional parameter threaded through eight files but the ONLY source of routes.
An optional parameter on a deep call chain cannot be distinguished from an empty
one, and eight attempts have now shown that every partial route to the answer
gets swallowed by exactly that property.

## Attempt nine: the thread works; the predicate is the problem

This attempt found the bug that made attempt eight a silent no-op, and then hit
the real wall.

**Bug found (why attempt eight matched nothing).** `canonicalAllows` compared
`ifName` -- the MODELLED name, `ens6` -- against the rendered network unit name,
`10-ens6`. Measured with the prefix removed:

```
rendered policy routes on s-router-policy : 363
matched on (interface, table, dst)        : 109   (with the 10- prefix stripped)
matched with the raw rendered name        :   0
```

So the code was correct except for a prefix, and `0` looked exactly like "no
canonical data reached me". Confirmed separately that the data does arrive, with
a trace on the list length after fixing the plumbing:

```
trace: CANLEN=385
trace: CANLEN=385
```

**The real wall.** With the plumbing correct, the filter is too strict. It asks
for `(interface, table, destination)` equality, and the renderer frequently
installs a route in a *different table* than the model names -- the
table-assignment defect, which this document already established is independent
of the duplication. Result: 12 test failures, because routes the model DOES
declare are dropped when their table differs.

```
PASS: 101, SKIP: 1, FAIL: 12  (baseline is 110 / 1 / 3)
```

Reverted. The attempt confirms both halves of the diagnosis with numbers:

1. the filter cannot be `(interface, table, destination)` equality while the
   renderer still chooses tables, so de-duplication alone cannot work;
2. the table choice must come from the canonical record FIRST, before any
   filtering is meaningful.

That is the same conclusion as attempts four, six and seven, now with the
plumbing proven and the exact prefix bug named. The next attempt should change
`tableForOutputIfName`/`tableForRoute` to return the canonical `tableId` for the
route's `(interface, destination)`, and only then apply the filter.

## Attempt ten: the canonical table was written and did not reach the unit

Reverted. Implemented the ordering attempt nine demanded: `canonicalTableFor`
looks up `(runtimeIfName, dst)` in `canonicalRoutes` and `withCanonicalTable`
rewrites each emitted route's `Table` to that value, applied in
`interface-units.nix` right before `routes = map stripRouteMetadata (...)`.
Verified `canonicalRoutes` with 385 entries reaches this file (a trace printed
the count in attempt nine, and the plumbing was unchanged).

Result: **no change**. Still 115 duplicate rows in
`FS-310-HDS-020-SDS-010-SMS-060`, and the suite is unchanged at 110 PASS / 3
FAIL. Rendered `10-ens6` still carries `100.64.0.2/32` in tables 1002, 1003,
1004, 1005 and 1006, while the model names exactly one (`ens6` / 1004):

```
["t=1002 100.64.0.2/32","t=1002 ...","t=1003 ...","t=1004 ...","t=1004 ...",
 "t=1005 ...","t=1006 ...","t=1006 ..."]
```

So the code is present and parseable, the value arrives, and the rewrite still
does not appear in the output. Either `networkForInterface` is not the producer
of those routes, or a later `mkMerge`/`mkForce` overwrites `Table`.

Checked where else a `10-<name>` network unit is written
(`public-ingress/container-forwards.nix`, `dns-services.nix`,
`pppoe-vlan-bridge.nix`, `systemd-host-network/*.nix`): none of them emit
container policy-table routes for these interfaces. That is as far as static
reading goes.

### What ten attempts have established

| attempt | change | outcome |
| --- | --- | --- |
| 1-2 | dedupe by iteration order | deleted the declaring route; core return-route tests red |
| 3 | de-dupe by own table | SMS-060 green, then DMZ routes missing (masking exposed) |
| 4 | stamp source allocation in raw-routes | no effect: stamping is not installing |
| 5-6 | tableForOutputIfName -> output allocation | no effect on the copies |
| 7 | routeOutputInterface returns source | SMS-060 target green legitimately, FS-540-SMS-040 red |
| 8 | filter at final assembly | matched nothing: compared `ens6` with `10-ens6` |
| 9 | same, prefix fixed | 109/363 match, but 12 tests red: tables differ |
| 10 | rewrite Table from canonical | no effect at all |

Each attempt disproved one hypothesis and none was wasted, but the remaining gap
is the same in every one: the rendered route set and the canonical route set are
produced by two independent code paths, and nothing in this repository
establishes which one actually reaches networkd. That is the question a
successful fix must answer first -- with a runtime check, not more static
reading.

## Attempt eleven: the runtime answer to attempt ten's question

Reverted, but it answered the question attempt ten left open, with a runtime
observation rather than more static reading.

**Q: which code path supplies the routes that reach networkd?**

A: `interface-units.nix`. Proven by injection, not by inspection. Appending one
synthetic route to `renderedRoutes` at the emit point:

```nix
) (renderedRoutes ++ [ { Destination = "203.0.113.77/32"; Table = 9999; ... } ])
```

made that route appear on **all six** interfaces of `s-router-policy`:

```
["10-ens3","10-ens4","10-ens5","10-ens6","10-ens7","10-ens9"]
```

So the emit point is real, it is evaluated per interface, and it is the final
source. The route list is built once and rendered under each interface's unit
name -- which is also why the same prefix can appear on every interface.

**Two distinct bugs, both now identified, both in my own attempts:**

1. **`canonicalRoutes` is empty at that point.** Traced directly:

   ```
   trace: CAN_EMPTY at p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-client--uplink-wan
   trace: CAN_EMPTY at p2p-s-router-policy-...--uplink-nebula
   ```

   The value did reach the file in attempt nine (`CANLEN=385`) but only after the
   whole `container-networks.nix` -> `interface-units.nix` chain was wired; the
   minimal rewrites in attempts ten and eleven dropped that wiring again. This is
   exactly the "optional parameter on a deep call chain" trap this document
   already names.

2. **`ifName` at that point is the MODELLED p2p name.** The trace prints
   `p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-admin--uplink-nebula`,
   not `ens6`. `canonicalRoutes.runtimeIfName` is `ens6`. So even with the list
   populated, the comparison `runtimeIfName == ifName` cannot match: the
   renderer's emit path is keyed by the modelled *attachment* name while the
   canonical record is keyed by the *rendered* interface name.

**The fix that follows from this**, concretely:

- translate `ifName` (modelled attachment name) to the rendered interface name
  before the lookup -- `renderedInterfaceNames` is already in scope at that
  point and is the intended mapping;
- thread `canonicalRoutes` all the way to `interface-units.nix` and make it a
  REQUIRED argument there (no `? [ ]`), so a dropped wire is an evaluation error
  instead of a silent no-op;
- then rewrite `Table` from the canonical record; the earlier 12-test failure
  should not recur because the table now comes from the model, not from the
  renderer's derivation.

None of that was applied: attempt eleven was still building the wiring when the
trace answered the question, and applying a third half-wired variant would repeat
the trap. The three steps above are the whole remaining change, each with the
specific evidence that justifies it.

## Attempt twelve: the lookup WORKS, and the rewrite is proven to reach output

Reverted, but this attempt got the mechanism working end to end for the first
time. Two results that all earlier attempts lacked:

**1. The emit path is confirmed by injection.** Appending one synthetic route to
`renderedRoutes` made it appear on all six interfaces of `s-router-policy`
(`10-ens3` .. `10-ens9`). `interface-units.nix` is the final source of the routes
that reach networkd -- attempt ten's open question, answered by observation.

**2. The canonical table lookup works.** With `canonicalRoutes` threaded
(required, not defaulted) and the modelled name translated through
`renderedInterfaceNames`, rewriting `Table` from the canonical record CHANGED THE
OUTPUT:

```
before: 10-ens6 carried 100.64.0.2/32 in tables 1002, 1003, 1004, 1005, 1006
after : 10-ens6 carried 100.64.0.2/32 in table 1004 x8   <- the one the model names
```

So every piece of the mechanism is now demonstrated: the code path, the data
reaching it, the name translation, and the table rewrite landing in the rendered
output.

**What still fails.** 11 tests, because the rewrite is unconditional wherever
the model names a single table, and several of those cases are ones where the
renderer's own table was correct for a reason the model does not express -- the
hostile-lane returns (`FS-540-SMS-040`: `::/0` modelled on five interfaces,
where any single-table rule discards the rest), and the FS-800 contracts. An
ambiguity guard (only rewrite when the model names exactly one table for the
pair) reduced the damage but not to zero.

Reverted to the 110 PASS / 3 FAIL baseline.

**So the remaining work is not the mechanism -- it is the policy.** The
mechanism works. What is missing is the rule for when the canonical table
overrides the renderer's: it cannot be "always", because some rendered tables are
correct and unmodelled, and it cannot be "never", because that is the defect.
Establishing that rule needs the FS-800 and FS-540 expectations read as a whole
rather than discovered one red test at a time, which is what the last four
attempts have been doing.
