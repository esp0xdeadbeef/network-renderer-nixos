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
