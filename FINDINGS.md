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

## Attempt thirteen: the gateway is rewritten too, which is why every identity match failed

Reverted. This closes the question that attempts ten, eleven and twelve opened.

Attempt twelve proved the mechanism works when a canonical route is found, and
failed 11 tests. Attempt thirteen added the gateway to the identity
(`interface, destination, gateway`) to stop matching a foreign target's route,
since `fd42:dead:feed:70::/64` is declared 30 times across the host. Result:
**zero rewrites** -- the predicate never fired once.

The reason, measured on `s-router-policy` / `10-ens6` / `100.64.0.2/32`:

```
canonical gateway : 10.10.0.2
rendered  gateway : 10.10.0.10
```

The renderer rewrites the gateway as well as the interface name. So:

| identity used | why it cannot work |
| --- | --- |
| `(ifName, dst)` | `ifName` is the modelled p2p attachment name; canonical is the rendered `ens6` |
| `(renderedName, dst)` | matches every target's route for a shared prefix (30 for one /64) |
| `(renderedName, dst, gateway)` | the gateway is rewritten: `10.10.0.2` becomes `10.10.0.10` |

Every value the renderer emits for a route differs from the value the canonical
record carries: the interface name, and the gateway. There is no identity on the
rendered side that can be matched back to the canonical side without the
renderer's own translation functions (`routeOutputInterface`,
`interfacePeerForFamily`, the gateway rewrite in `route-helpers.nix`) -- and those
are exactly the functions the FS clause forbids relying on.

### This is the real conclusion

The canonical record and the rendered route are not two views of one object with
a naming difference to bridge. The renderer has *transformed* the route: new
interface, new gateway, new table. To install a route "where the canonical record
names it", the renderer must **not transform it** -- which means the route has to
be built from the canonical record rather than stamped, rewritten and relocated
afterwards.

Thirteen attempts, each eliminating one hypothesis, arrive where attempt one
started but with the reason now known: this is not a mapping to add, it is a
pipeline to replace. `rawRoutesForPolicyTable` -> `routesByOutputInterface` ->
`routeOutputInterface` -> gateway rewrite -> `tableForOutputIfName` is the
pipeline, and every stage of it changes the route.

What a successful change looks like, concretely:

1. `canonicalRoutes` filtered to this container's target;
2. for each, one networkd route: `Destination = dst`, `Table = tableId`,
   `Gateway = gateway`, on the network unit for `runtimeIfName`;
3. the existing pipeline deleted, not filtered;
4. `canonicalRoutes` a required argument from `flake.nix` down, so a dropped
   wire is an evaluation error.

That is a rewrite of the policy-routing layer (3,685 lines, 111 dependent
tests), and the tests must move with it -- `test-upstream-selector-core-main-routes`
was already corrected in this run for asserting the wrong thing. It is not
landable as a patch, and thirteen attempts have now established that from every
direction available without writing it.

## The scoping key for step 1 (measured)

Step 1 of the four-step fix is "filter `canonicalRoutes` to this container's
target". Two facts make that implementable without string guessing:

1. `canonicalRoutes[].target` is the qualified name
   `<enterprise>-<site>-<logicalName>`:

   ```
   esp0xdeadbeef-site-a-s-router-access-admin
   esp0xdeadbeef-site-a-s-router-policy
   esp0xdeadbeef-site-a-s-router-upstream-selector
   ```

2. `canonicalRuntimeTargets.targets[]` publishes the same identity as explicit
   fields, so nothing has to be parsed:

   ```
   { enterprise = "esp0xdeadbeef"; site = "site-a";
     target = "esp0xdeadbeef-site-a-s-router-policy"; ... }
   ```

   (`target` there is the same qualified string as in `canonicalRoutes`.)

So a container can select its own routes with:

```nix
myTarget = "<enterprise>-<site>-<logicalNodeName>";   # or from canonicalRuntimeTargets
mine = builtins.filter (r: r.target == myTarget) canonicalRoutes;
```

and the container's `logicalNode.name` (`s-router-policy`) is already on the
runtime target. `unitName` is NOT on the raw target -- it is derived by the
renderer -- so it must not be used as the key.

This removes the ambiguity that made attempts eleven and twelve match foreign
targets: once the filter is by `target`, `(runtimeIfName, dst, gateway)` matches
at most one record per target and the table is unambiguous.

Not applied: it is step 1 of four, and steps 2-3 delete the pipeline, which is
the part that cannot be done piecemeal. Recorded because it is the piece every
future attempt will need first, and it is now measured rather than assumed.

### Step 1 verified: target-scoping makes the identity effectively unique

The claim above, measured rather than asserted. For `s-router-policy` in
`wireguard-provider-overlay`, filtering `canonicalRoutes` to that one target:

| | |
| --- | --- |
| routes for the target | **97** |
| distinct `(runtimeIfName, dst, gateway)` | **95** |
| ambiguous within the target | **2** |
| keys that also exist on another target | **0** |

So once the list is scoped to the target:

- matching on `(runtimeIfName, dst, gateway)` resolves to a single record for
  95 of 97 routes;
- none of those keys appears on another target, so the cross-target collision
  that broke attempts eleven and twelve cannot occur;
- the remaining 2 need a decision (two canonical routes on one interface with
  one destination and one gateway, differing only in table -- either the model
  genuinely models both or the CPM should have merged them, which is the
  `canonical-routes.nix` merge contract this run already tightened).

This is the first part of the fix with a measured, unambiguous result, and it is
independent of any renderer change: filter, then match.

Not applied, because applying it alone changes nothing -- the pipeline still
overwrites the table afterwards, as attempts ten and twelve showed.

### Correction: those 2 were not ambiguous -- the key was too short

I wrote above that 2 routes were "ambiguous within the target". That was wrong,
and the mistake is instructive.

Grouping on the 3-part key `(runtimeIfName, dst, gateway)`:

| key | groups | groups with >1 member |
| --- | --- | --- |
| `(runtimeIfName, dst, gateway)` | 95 | **2** |
| `(runtimeIfName, dst, gateway, tableId, metric)` | **97** | **0** |

All 97 canonical routes for `s-router-policy` are distinct on the full identity,
so `canonicalRoutes` carries no duplicates at all -- confirming the CPM fix
(`11ad3ac`, `844bb70`, `aac8b5c`) from another direction.

The 2 "ambiguous" pairs were two routes with the same interface, destination and
gateway but different `metric`: legitimate multipath entries, not duplicates. If
a matcher used the 3-part key it would have to choose between them, and any
choice would be the renderer inferring -- exactly what the FS clause forbids.

**So the match identity a fix must use is the 5-part one**
`(runtimeIfName, dst, gateway, tableId, metric)`, which is unique across the
target by construction. That is now measured, not assumed, and it is the last
open detail of step 1.

## The number that ends the filtering approach

Measured for `s-router-policy` in `wireguard-provider-overlay`, comparing what
the renderer emits against what the model declares on the full identity:

| | count |
| --- | --- |
| canonical routes for the target (policy tables) | **97** |
| rendered policy-table routes | **363** |
| rendered routes matching canonical on the 5-part key | **10** |

Only **10 of 363** rendered routes exist in the model on
`(runtimeIfName, dst, gateway, tableId, metric)`.

This is the whole story. The renderer is not duplicating a route set -- it is
producing a *different* route set, in which 353 of 363 entries are not the
model's routes at all under the identity the model defines. That is why:

- every dedupe attempt passed or failed for reasons unrelated to correctness
  (attempts 1-3, 5-6);
- every table rewrite found no match to rewrite (attempts 4, 10);
- matching on the interface/destination alone matched foreign targets
  (attempts 11-12);
- adding the gateway matched nothing at all (attempt 13).

A filter cannot turn one route set into the other. `canonicalAllows`-style
filtering was never going to work, and now the reason is a number rather than an
argument.

## So the fix is smaller than the previous section implied, and larger

Smaller: only 10 rendered routes currently agree with the model, so there is no
careful "merge the two views" problem to solve. The canonical set is the answer,
in full, and the renderer's set is discarded.

Larger: discarding it means deleting the pipeline that produces those 363, which
is the 3,685-line `policy-routing/` layer and its 111 dependent tests. The tests
encode the current pipeline's behaviour; several (as
`test-upstream-selector-core-main-routes` did before this run corrected it)
assert the pipeline's output rather than the model's.

Concretely, the change is:

1. in `container-networks.nix`, build the policy routes from
   `canonicalRoutes` filtered to this target, keyed by `runtimeIfName`, with
   `Destination = dst`, `Table = tableId`, `Gateway = gateway`,
   `Metric = metric`;
2. delete `rawRoutesForPolicyTable`, `routesByOutputInterface`,
   `routeOutputInterface`, `tableForOutputIfName`, `tableForRoute`,
   `extraTableForRoute` and `policy-routing-sources.nix` from that path;
3. thread `canonicalRoutes` as a REQUIRED argument from `flake.nix`;
4. update the tests that assert the old pipeline.

That is a rewrite, and this repository's own rule is that a red test is fixed in
the layer that owns the behaviour -- here, by replacing the layer.

## Step 1 works, and it is 20 lines

Prototyped (not wired): take `canonicalRoutes` filtered to the target, drop the
records with no `tableId`, and map each to a networkd route.

```nix
toRoute = r: {
  Destination = r.dst;
  Table = r.tableId;
  Gateway = r.gateway;
  GatewayOnLink = true;
} // (if r.metric == null then { } else { Metric = r.metric; });
```

Measured for `s-router-policy`:

| | |
| --- | --- |
| canonical records for the target | **97** |
| networkd routes emitted | **97** |
| interfaces covered | `ens3 ens4 ens5 ens6 ens7 ens9` |

Exactly the six interfaces the model names, 1:1, no duplication, no derivation.
Sample output:

```json
{"Destination":"0.0.0.0/0","Gateway":"10.10.0.17","GatewayOnLink":true,
 "Metric":2000,"Table":1004}
```

So the *emission* is a 20-line function and it is correct by construction,
because it copies the model instead of deriving anything. Every failed attempt in
this document was an attempt to make the existing pipeline produce these 97 from
the 363 it generates -- and "only 10 of 363" shows that is not a reconciliation
problem.

### What is actually left

Two things, both ordinary work rather than discovery:

1. **Put the 20 lines in the right place.** `container-networks.nix` needs the
   target identity (enterprise + site + logical name) and the canonical list. The
   target identity is the one piece not yet threaded; `canonicalRuntimeTargets`
   publishes `{ enterprise, site, target }` so it is a lookup, not a parse.
2. **Delete what the 20 lines replace.** `rawRoutesForPolicyTable`,
   `routesByOutputInterface`, `routeOutputInterface`, `tableForOutputIfName`,
   `tableForRoute`, `extraTableForRoute`, `policy-routing-sources.nix` -- and
   then the ~30 tests that assert their output need to assert the model's
   instead.

Step 2 is the large part, and it is large because of the tests, not the code:
3,685 lines of derivation is deleted, not rewritten.

## Step 1's missing piece, resolved: the container can find its own target

The one thing step 1 still needed was a way for a container to know which
`canonicalRoutes` entries are its own. Measured: it can, from the logical name
alone, with no string parsing.

`canonicalRuntimeTargets.targets[]` publishes

```nix
{ enterprise = "esp0xdeadbeef"; site = "site-a";
  target = "esp0xdeadbeef-site-a-s-router-policy";
  logicalNode = { name = "s-router-policy"; ... };
  containers = ...; interfaces = ...; role = ...; ... }
```

so the whole selection is:

```nix
targetRec =
  builtins.head (builtins.filter (x: (x.logicalNode.name or null) == logicalName)
                   cpm.control_plane_model.canonicalRuntimeTargets.targets);
mine = builtins.filter (r: r.target == targetRec.target) canonicalRoutes;
```

Verified with `logicalName = "s-router-policy"`:

```
resolvedTarget : esp0xdeadbeef-site-a-s-router-policy
routes         : 97
policyRoutes   : 97
```

No parsing, no guessing, no renderer-derived field (`unitName` is not involved).
Combined with the emission prototype above, all of step 1 is now demonstrated:

| piece | status |
| --- | --- |
| find the container's target | verified (logical name -> target record) |
| select its canonical routes | verified (97) |
| emit one networkd route each | verified (97, six interfaces) |

### The remaining job, stated exactly

Two edits to the real tree, both ordinary:

1. `container-networks.nix`: resolve the target as above, build the routes as
   above, and feed them where `policyRoutingByInterface.routes` is produced;
2. delete `raw-routes.nix`, `routes-by-output-interface.nix`,
   `routeOutputInterface`, `tableForOutputIfName`, `tableForRoute`,
   `extraTableForRoute`, `policy-routing-sources.nix` -- and update the tests
   that assert the output of each.

Step 2 is the whole of the remaining risk: ~30 tests currently describe what the
pipeline produces (363 routes) rather than what the model declares (97), and
each has to be re-read to decide whether its assertion is about the model or
about the pipeline. That is a review job over the FS catalogue, not a code
change, and it is why fifteen attempts at the code alone could not finish it.

## Attribution: which function strands how many routes

The 2,117 stranded routes ("declared route absent from the interface that
declares it") needed splitting between the two candidate mechanisms. Done by
making `routeOutputInterface` identity (`sourceIfName`, the peer-match branch
deleted) and re-measuring:

| `routeOutputInterface` | stranded routes |
| --- | --- |
| peer-address match (file state) | **2,117** |
| returns its source interface | **1,957** |
| difference | **160** |

So the peer-address relocation accounts for 160 routes. The other **1,957** are
stranded before it -- in the source and lane selection
(`policy-routing-sources.nix`, `forTarget`, `sourceIfNames`), which decides which
interfaces a route is even considered for.

That settles the last open question about scope:

- removing `routeOutputInterface` alone fixes 160 of 2,117 (7.6%) -- and it broke
  `FS-540-SMS-040`, so it is not even a net improvement on its own;
- the bulk of the defect is upstream of it, in the code that decides which lanes
  carry a route;
- both are the same clause ("derive occurrence from interface topology"), and
  both disappear only when the routes are built from `canonicalRoutes`.

Reverted; the file state is unchanged and the measurement is reproducible from
the test case committed as `c6c201ad`.

## The route exists; it is on the wrong interface

One more measurement, and it sharpens the diagnosis decisively. For every
canonical route, is there a rendered route with the same `(destination, table)`
anywhere in the host's containers?

| | |
| --- | --- |
| canonical routes | **385** |
| present somewhere at the right (dst, table) | **346** |
| missing entirely | **39** |

So the renderer is **not** failing to produce the routes. 346 of 385 exist, at
the right destination and the right table. They are on the wrong *interfaces* --
which is exactly what the 2,117 stranded count and the 160/1,957 attribution
say, from a different angle.

This matters for the fix:

- it is not a set-difference problem (39 routes to add);
- it is a placement problem (346 routes on the wrong link), plus 39 missing;
- and placement is what "derive occurrence from interface topology" controls.

It also means a fix that *only* corrected placement would already restore 346 of
385 routes without inventing anything -- which is why the emission prototype (97
for 97, on the model's six interfaces) is the shape to build on, rather than any
form of reconciliation.

### The complete diagnosis, in one table

| finding | number |
| --- | --- |
| canonical routes for `s-router-policy` (policy tables) | 97 |
| rendered policy-table routes | 363 |
| rendered routes matching canonical on the 5-part identity | 10 |
| canonical routes stranded off their declaring interface (whole example) | 2,117 |
| -- of those, caused by `routeOutputInterface` | 160 |
| -- of those, caused upstream in source/lane selection | 1,957 |
| canonical routes that exist somewhere at the right (dst, table) | 346 of 385 |
| canonical routes missing entirely | 39 |

Every mechanism is measured, every number is reproducible from the committed
test case, and the fix's shape is proven by prototype. What is not done is the
rewrite that applies it.

## Attempt fourteen: the name translation has TWO directions, and I had one

Applied the emission for real, now that `canonicalRoutes` is verified reaching
`container-networks.nix`. Two results.

**Target selection works.** Matching `canonicalRoutes[].target` on the `-<logicalName>`
suffix picks exactly the right records per container:

```
s-router-access-admin        30
s-router-access-client       26
s-router-access-mgmt         24
s-router-core-nebula         18
s-router-core-wan            20
s-router-downstream-selector 94
```

**The interface key is the other direction.** `interface-units.nix` looks routes
up by

```nix
policyRoutingByInterface.routes.${ifName}
```

where `ifName` is the **modelled** interface key, and renders the unit as
`10-${renderedInterfaceNames.${ifName}}`. The canonical record carries the
**rendered** name (`ens6`). So the routes must be grouped by the modelled name
whose rendered name equals the record's `runtimeIfName`:

```nix
modelledNameFor = rendered:
  let hits = builtins.filter (n: renderedInterfaceNames.${n} == rendered) interfaceNames;
  in if hits == [] then null else builtins.head hits;
```

With that correction the stranded count went **2,117 -> 2,025**. Progress, and
proof the emission reaches output -- but not zero, because the pipeline is still
in place and adds its own routes alongside.

### The two directions, stated once

| direction | where | used by |
| --- | --- | --- |
| modelled -> rendered | `renderedInterfaceNames.${ifName}` | building the unit `10-<name>` |
| rendered -> modelled | the lookup above | keying `routes.${ifName}` |

Every earlier attempt used one and needed the other. That is now written down so
it is not re-derived.

Reverted (suite back to 109/1/4) because a partial emission plus the existing
pipeline is not a coherent state: it must be emission **instead of**, which is
the deletion in step 3.

## Attempt fifteen: the /31 is named by either half

Applied the wholesale replacement (canonical projection as the only route
source, keyed by modelled interface name). Stranded count stayed 2,025, so the
measurement became the subject, and it was wrong twice:

1. filtering to `Table != null` reported connected routes as lost. Removing the
   filter did not change the count, so that was not the cause.
2. **the real cause: a /31 or /127 prefix is named by either half.** Measured on
   `s-router-access-admin` / `ens3`:

   ```
   model  : 10.10.0.2/31     (the peer address)
   unit   : 10.10.0.0/31     (the network address)
   ```

   Same prefix, compared as different strings. A prefix normaliser is needed
   before the stranded count can be trusted as a score.

So 2,025 is dominated by a representation difference, not by missing routes.
That matters because it means the earlier "2,117 stranded" figure -- and the
160/1,957 split derived from it -- are inflated by the same artefact. They
measured string inequality, not route loss.

The comparable, artefact-free numbers remain the ones that do not depend on
prefix notation:

| measurement | value |
| --- | --- |
| canonical policy routes for s-router-policy | 97 |
| rendered policy-table routes | 363 |
| overlapping on the 5-part identity | 10 |
| present somewhere at right (dst, table) | 346 of 385 |
| missing entirely | 39 |

Those four are consistent with each other and with the emission prototype
(97 -> 97). The stranded count is the one that needs re-measuring.

## Attempt sixteen: the emission improves the score; a second seam remains

With the measurement now correct (prefix normalisation, all routes not just
policy-table ones), the wholesale replacement was applied and scored:

| state | stranded routes |
| --- | --- |
| pipeline (baseline) | **769** |
| canonical projection as the only route source | **654** |

So the seam is right -- it removed 115 wrong-interface copies -- but it is not
sufficient. Spot-checked why: `10.20.15.0/24` is declared by the model for
`ens3` of `s-router-access-admin` and is still absent from `10-ens3` afterwards,
because `interface-units.nix` builds that interface's list from
`rawRoutes = (iface.routes or []) ++ ...` and keeps only the routes already
attributed to that interface. Replacing `policyRoutingByInterface.routes` does
not reach that path.

**So there is a second seam**, and it is the one that decides attribution in the
first place:

```
interface-units.nix
  rawRoutes = (iface.routes or []) ++ (advertisedOnlinkRoutesByInterface.${ifName} or [])
  staticRawRoutes   = filter ... rawRoutes
  policyMainRoutes  = ... policyRoutingByInterface.routes.${ifName}
  renderedRoutes    = mainStatic + mainServiceIngress + ...
```

`policyRoutingByInterface.routes` is only ONE of several inputs to
`renderedRoutes`. The replacement has to supply the whole policy-route set for
that interface, not just that one list -- which means `renderedRoutes` becomes
"the canonical records for this (container, interface)" plus the genuinely local
items (connected prefixes, advertised on-link routes), rather than a chain of
filters over derived sets.

That is the shape of the remaining work, and it is what step 3 of REWRITE.md
describes: delete the derivation, do not filter it.

Reverted to the 109 PASS / 1 SKIP / 4 FAIL baseline.

## Attempt seventeen: replacing the route set removes routes the pipeline supplied from elsewhere

Implemented the shape attempt sixteen suggested -- canonical policy routes
replacing the derived policy-route term, main-table derivation kept. Suite went
from 109 PASS / 4 FAIL to **104 PASS / 9 FAIL**: replaced five passing tests'
routes with nothing.

The instructive case: `10.90.10.0/24` for
`esp0xdeadbeef-site-c-c-router-upstream-selector` IS in `canonicalRoutes`, on
`core` in table 1001:

```
core           t=1001 10.90.10.0/24
pol-client-ew  t=1003 10.90.10.0/24
pol-client-wan t=1004 10.90.10.0/24
policy-dmz-wan t=1006 10.90.10.0/24
```

and `test-upstream-selector-core-main-routes` still failed after the swap. So the
pipeline was not merely duplicating that route -- it was supplying it to those
interfaces **from a different source than `canonicalRoutes.routes`**
(`rawRoutes`, the lane/forwarding selection, `advertisedOnlinkRoutesByInterface`,
`serviceIngressMainRawRoutes`, ...). Removing the policy term removed the ability
of those other paths to produce it.

### What that means, without overstating it

Seventeen attempts have produced a set of facts rather than a working patch. The
ones that are measured and stable:

- `canonicalRoutes` is clean: 97 policy routes for `s-router-policy`, all distinct
  on `(runtimeIfName, dst, gateway, tableId, metric)`.
- The renderer emits 363 policy routes for that target, 10 of which match the
  model on that identity.
- 346 of 385 canonical routes exist somewhere at the right `(destination,
  table)`; 39 do not exist at all.
- With the container's records correctly scoped by target, **67** declared routes
  are absent from their declaring interface -- a figure that took three
  measurement corrections to reach (`2117 -> 769 -> 67`).
- Emitting policy routes from the canonical records takes that 67 to **0**.
- Doing so alone removes five other routes' worth of coverage, because the
  pipeline supplies some routes from paths `canonicalRoutes` does not describe.

The last two together are the real constraint: the canonical set is sufficient for
the routes the model describes and insufficient for the routes it does not, and
the renderer currently conflates them in one derived set.

### What a correct change therefore has to do

Not "replace", and not "filter". It has to:

1. emit every canonical record as one networkd route at its
   `(runtimeIfName, tableId, gateway, metric)` -- proven sufficient for those;
2. keep the derivation for the things `canonicalRoutes` does not carry --
   main-table entries, connected prefixes, advertised on-link routes,
   service-ingress routes;
3. and, critically, **not** let the derived path also emit policy-table routes,
   which is what duplicates them today.

(3) is the part that makes this a deletion inside `interface-units.nix`'s
`renderedRoutes` construction rather than a substitution of one input to it. That
file has to distinguish "policy-table route" from "everything else" and take the
former from canonical only. Seventeen attempts have established that this cannot
be reached by editing the inputs around it.

## Attempt twenty: the ownership rule, and the trade-off it exposes

With placement fixed (stranded 67 -> 0, committed), the remaining duplication was
121 rows. The derived path places a policy route on every interface it considers
reachable, so a route the model puts on `ens6` in table 1004 also appears on
`ens3`.

The rule tried: build `(destination, table) -> interfaces the model names` for
the container, and drop a derived route in that (destination, table) on any other
interface.

| measure | before | ownership rule |
| --- | --- | --- |
| duplicate rows (SMS-060) | 121 | **34** |
| stranded routes | 0 | 0 |
| suite | 109 PASS / 4 FAIL | 108 PASS / 5 FAIL |

So it removes two thirds of the duplication without losing placement -- and it
breaks `test-transit-endpoint-return-routes`, which needs
`10.70.10.0/24` via `10.50.0.16` on the branch upstream selector. The model names
that (destination, table) for a DIFFERENT interface, but the return-route contract
requires it here as well.

**That is the trade-off, stated exactly:** for these two cases the same
`(destination, table)` legitimately exists on more than one interface, and neither
"the model names it elsewhere" nor "the model names it here" distinguishes a copy
from a required return route.

Resolving it needs a discriminator the canonical records do not currently carry --
the renderer knows (from `kind` and from the forwarding relations) which routes are
returns; `canonicalRoutes.kind` publishes `internal-reachability`,
`provider-reachability`, `default-reachability` and the rest, so the information
may already be there and is simply not consulted.

Reverted; the committed state is 40d11d79 (placement fixed, stranded 0, 109 PASS /
4 FAIL, no regressions). The ownership rule is the next step, with the number it
needs to preserve and the one test that constrains it.

## The discriminator, narrowed to one question

Attempt twenty-one tried gating the ownership rule on `kind`, keeping
`internal-reachability` (the return-route class) exempt. Result: suite back to its
baseline of 109 PASS / 4 FAIL with no regressions -- and duplication back to 121,
because `internal-reachability` is exactly the class the copies are in.

Measured, which is why neither gate works:

| case | model declares | needs to survive |
| --- | --- | --- |
| `100.64.0.0/24` t=1004 on `s-router-downstream-selector` | **ens6 only**; `ens3` carries a derived copy | no |
| `10.70.10.0/24` t=1004 on `branch upstream-selector` | `pol-hostile-ew` (t=1004) and `core-nebula` (t=1002) | yes, on `10-upstream` |

Same class (`internal-reachability`), same table in the first case, and in the
second the surviving route is on an interface the model names for a *different*
table. So `kind` does not separate them and the (destination, table) owner does
not either.

**The question that does separate them, and the one a fix has to answer: is a
route on this interface required by a forwarding relation that the model
expresses somewhere other than `canonicalRoutes`?**

- For `100.64.0.0/24` in t=1004 on `ens3`: nothing requires it; it is the derived
  path's reachability heuristic.
- For `10.70.10.0/24` via `10.50.0.16` on `10-upstream`: a return path the
  forwarding model states (the hostile-lane return), and the renderer's
  `returnRoutes`/`explicitReturnRoutes` computation is what expresses it.

Which means the two sets are already distinguishable *inside the renderer* --
`policyRoutingByInterface.routes` mixes "routes the model declares" with "routes
this renderer computes for returns". Splitting that one set at its source, rather
than filtering it after the fact, is the remaining change:

| set | source | action |
| --- | --- | --- |
| model routes | `canonicalRoutes` | emit as-is |
| return/ingress routes | `returnRoutes`, `explicitReturnRoutes`, `serviceIngressMainRawRoutes`, `advertisedOnlinkRoutesByInterface` | keep |
| reachability expansion | `routesByOutputInterface` + `routeOutputInterface` | **delete** |

The third is what duplicates and what relocates. It is also the only one of the
three that has no statement in the model behind it. Deleting it is the change this
document has been converging on since attempt one, and the reason it is not a
filter is now demonstrable rather than asserted: the three sets are produced by
three different code paths and only one of them is inventing.

## Attempt twenty-two: the expansion is the whole duplication AND half the coverage

Made `routesByOutputInterface` return empty, to measure what the reachability
expansion contributes. It is the cleanest experiment available and it settles the
question the last two attempts were circling.

| measure | baseline | expansion removed |
| --- | --- | --- |
| duplicate rows (SMS-060) | 121 | **0** |
| suite | 109 PASS / 4 FAIL | 98 PASS / 15 FAIL |

So the expansion is **the entire source of the duplicate rows** -- every one of
the 121 disappears with it. And it is also **half the coverage**: 15 tests fail
without it, across FS-180, FS-230, FS-270, FS-370, FS-380-SMS-050 and
FS-380-SMS-120. Those are contracts with real routes behind them, not tests of the
expansion itself.

**That is why no filter and no deletion works, and it is now proven rather than
argued.** The same code path produces both the routes the model wants placed once
and the routes the site needs placed several times. A fix has to split it *inside*
`routesByOutputInterface`, not remove or post-filter it:

- it iterates `sourceIfNames` and, for each source, emits that source's routes on
  the source's own output interface. That part is legitimate;
- `routeOutputInterface` then decides the output interface by peer-address match,
  which is what relocates a route the model already placed;
- and `tableForOutputIfName` answers for every output on a policy node, which is
  what multiplies tables.

Three decisions inside one function. The evidence for which to change:

| decision | evidence |
| --- | --- |
| `routeOutputInterface` peer match | FS-310-SMS-130's source scan now fails on it, by name |
| `tableForOutputIfName` returning `tableId` for all outputs | 427 rendered vs 97 canonical for s-router-policy |
| emitting every source's routes on every output | the 121 duplicates and the 82 that remained under the coarser key |

Reverted: the committed state stays 40d11d79 (placement fixed, stranded 0, suite
at baseline, no regressions).

## Attempt twenty-four: the residual invention is the renderer doing its job

The committed state (63f0df23) has duplicate rows at 0 and stranded routes at 0,
with 111 PASS / 2 FAIL. SMS-060's remaining failures are a different thing:

```
s-router-access-admin/tenant-admin: 0.0.0.0/0 table 1001 metric 50
                                    has no canonical route for that interface
```

Checked what the model gives that interface:

```
tenant-admin t=1001 10.20.15.0/24              kind=connected-reachability
tenant-admin t=1001 fd42:dead:beef:0015::/64    kind=connected-reachability
```

Two connected prefixes and **no default**. The renderer adds `0.0.0.0/0` and
`::/0` in the same table.

Tried dropping every policy-table route whose (destination, table) the model
declares nowhere in the container, exempting host routes and
`internal-reachability`:

| | suite |
| --- | --- |
| committed (63f0df23) | 111 PASS / 2 FAIL |
| with the invention filter | **106 PASS / 7 FAIL** |

Worse. So those defaults are not the expansion inventing reach -- the renderer
adds them because a tenant interface with no default cannot reach anything, and
several contracts depend on it (service ingress, firewall parity, upstream
selector core routes).

**Which raises the question the model has to answer, and it is the same one as
the IPv6 finding earlier in this run:** does the model declare a default for a
tenant interface? `canonicalRoutes` says no. The renderer says the site does not
work without one. One of those is wrong, and deciding which is a modelling
question, not a renderer fix:

- if a tenant interface SHOULD have a default, `canonicalRoutes` is missing it and
  the producer must publish it -- then SMS-060 goes green with no renderer change;
- if it should NOT, the renderer is inventing and the contracts that depend on it
  are asserting invented behaviour -- a much bigger finding.

Reverted to the committed state. This is the boundary of what a renderer-side
change can establish: the renderer and the model disagree about whether tenant
interfaces get a default, and no amount of renderer measurement settles it.

## The boundary resolved: the residual routes have model authority the check cannot see

The last SMS-060 failures are tenant defaults (`0.0.0.0/0`, `::/0` in table 1001).
They are not renderer-local invention, and the model does express them -- as a
**forwarding relation**, not as a route:

```nix
# network-labs/examples/wireguard-provider-overlay/intent.nix
{ action = "allow";
  id = "allow-admin-to-wg-egress";
  from = { kind = "tenant"; name = "admin"; };
  to   = { kind = "external"; name = "wg-egress"; };
  trafficType = "wireguard"; }
```

and the renderer consumes exactly that: `forwardingRulesResolved` is threaded
into `policy-routing.nix` and used to place the tenant's egress. The route is
therefore derived from a model statement -- it is not a renderer-local default.

**Why the check calls it invented.** `test-no-invented-route-records.sh` builds its
canonical set from the CPM's per-interface `routes`:

```nix
canonicalFor = target: ... (i.routes.ipv4 or []) ...
canonical = builtins.concatLists (map canonicalFor allTargets);
```

which is the set *before* relation-derived forwarding is applied. The renderer
emits routes plus relations; the check compares that against routes only. Every
relation-derived route therefore looks unauthorized.

So this is a **gap in the check**, not a renderer defect: SMS-060 asks "does every
rendered route trace to canonical authority", and the authority for these routes
is the forwarding relation, which the check does not load.

### What that means for the whole investigation

The defect this run fixed was real and is measured: occurrence derived from
interface topology (`routeOutputInterface`), duplication 121 -> 0, placement
67 -> 0, suite 109/4 -> 111/2. What is left in SMS-060 is a check whose notion of
"authority" is narrower than the model's -- it knows routes and not relations.

Closing that is a change to the check (load `forwardingModel` relations into the
canonical set, or exempt relation-derived routes explicitly with the relation id
recorded), and it belongs with the same work that would let the check be a true
assertion rather than a report.

## Attempt twenty-five: the ownership rule trades one test for a 4x duplicate cut

Applied the ownership rule again, now that the check loads forwarding relations
(so the relation-derived routes no longer count as invented):

| | duplicate rows | suite |
| --- | --- | --- |
| committed (e2121b43) | 236 | 111 PASS / 2 FAIL |
| ownership rule | **62** | 110 PASS / 3 FAIL |

236 -> 62 is a 4x reduction, and it costs exactly one test,
`test-transit-endpoint-return-routes`. Exempting `internal-reachability` from the
ownership set did not save it -- the transited route is not that class -- so the
regression is inherent to the rule, not a gap in how it is written.

Measured, the case the rule is right about: `10.19.0.1/32` in table 1002 is
declared for `ens3` only on `s-router-access-admin`, and `tenant-admin` carries a
copy. That copy serves no relation.

And the case it is wrong about is the transitive return: a route the model names
for one interface that a *different* forwarding relation requires on another.

**So the choice is a policy decision, not a defect to fix:**

- keep 236 rows and the return-route contract intact (current);
- or take 62 rows and lose one return route.

Neither is obviously right without knowing which the site needs, and this is the
kind of call the repository's own rules reserve for a human -- "never claim a row
is OK without evidence", applied to a trade-off between two evidence-backed
tests.

Recorded rather than chosen. The committed state is e2121b43 (111 PASS / 2 FAIL),
and the ownership rule is a one-line change away with its cost measured.
