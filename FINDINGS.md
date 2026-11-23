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
