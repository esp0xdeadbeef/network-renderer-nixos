# The policy-routing replacement: the complete change, ready to apply

This is the handoff. Every prerequisite is resolved and measured; what remains is
applying it. `FINDINGS.md` has the full investigation (21 attempts); this file is
only the change.

## What is wrong, in numbers

All measured on `network-labs/examples/wireguard-provider-overlay`, all
reproducible from `tests/lib/FS-310-HDS-020-SDS-010-SMS-060/test-declaring-interface-keeps-its-route.nix`
(committed, currently reports rather than asserts).

| finding | number |
| --- | --- |
| canonical policy routes for `s-router-policy` | 97 |
| rendered policy-table routes for it | 363 |
| rendered routes matching canonical on the 5-part identity | 10 |
| canonical routes off their declaring interface (whole example) | 2,117 |
| -- caused by `routeOutputInterface` | 160 |
| -- caused by upstream source/lane selection | 1,957 |
| canonical routes present somewhere at the right (dst, table) | 346 of 385 |
| canonical routes missing entirely | 39 |

The renderer does not omit the routes: it puts 346 of 385 on the **wrong
interfaces**. Placement is what FS-310-HDS-020-SDS-010-SMS-060 forbids deriving:

> "The renderer shall not choose, infer, or withhold a route's table or lane
>  occurrence: it shall not gate a route's materialization on the presence of a
>  forwarding rule, **derive occurrence from interface topology**, or rely on an
>  environment-supplied fallback table."

Two functions do it:

- `policy-routing-sources.nix` -- decides, from interface class and lane
  (`hasClass`, `sameAccess`, `sameUplink`), which interfaces feed which policy
  table. The CPM publishes no `policyRoutingSources` anywhere, so this file is
  the sole author of every source set.
- `route-helpers.nix:routeOutputInterface` -- moves each route to the interface
  whose p2p peer address equals the route's gateway.

## The change

### 1. Emit from the canonical records

Verified working as a prototype (97 records -> 97 routes on the model's six
interfaces):

```nix
toRoute = r: {
  Destination = r.dst;
  Table = r.tableId;
  Gateway = r.gateway;
  GatewayOnLink = true;
} // lib.optionalAttrs (builtins.isInt (r.metric or null)) { Metric = r.metric; };
```

Select the container's records by target, resolved from its logical name -- no
parsing, verified:

```nix
targetRec = builtins.head (builtins.filter
  (x: (x.logicalNode.name or null) == logicalName)
  cpm.control_plane_model.canonicalRuntimeTargets.targets);
mine = builtins.filter (r: r.target == targetRec.target) canonicalRoutes;
```

Place them at `render/container-networks.nix`, where `policyRoutingByInterface`
is produced, and group by `runtimeIfName`.

### 2. Make `canonicalRoutes` reach there, as a required argument

Seven hops, and every one must be required -- not `? [ ]`. Three attempts were
lost to a silently-dropped wire on this chain (attempts eight, ten and eleven;
`canonicalRoutes ? [ ]` made every hop succeed at doing nothing):

```
flake.nix (canonical.hostModule)  cpm = validated.controlPlaneEnvelope
  -> render/containers.nix        canonicalRoutes from
                                  cpm.control_plane_model.canonicalRoutes
  -> render/containers/default.nix
  -> render/containers/inputs.nix
  -> render/containers/emission.nix
  -> render/containers/module.nix
  -> render/container-networks.nix
  -> render/container-networks/interface-units.nix
```

`container-networks.nix` does not currently receive `cpm`, which is why the
experiment above failed with `undefined variable 'cpm'`: step 2 is a
prerequisite of step 1, not an optional tidy-up.

### 3. Delete what this replaces

- `policy-routing/raw-routes.nix`
- `policy-routing/routes-by-output-interface.nix`
- `policy-routing/route-helpers.nix` (`routeOutputInterface`)
- `policy-routing/policy-routing-sources.nix`
- `tableForOutputIfName`, `tableForRoute`, `extraTableForRoute` in `aggregate.nix`
- the `matchingInterfaces`/`interfacePeerForFamily` path

`FS-310-HDS-010-SDS-010-SMS-130` already fails on the peer-address match, so
deleting it turns that test green and is the proof the deletion happened.

### 4. Then the tests

15 files touch this surface (ranked by `Table` references):
`FS-540-SMS-040` (58), `FS-380-SMS-050` (25), `FS-320-SMS-030` (23),
`FS-540-SMS-020` (21), `FS-380-SMS-120` (19+15), `FS-310-SMS-130` (11),
`test-upstream-selector-core-main-routes` (8), `test-transit-endpoint-return-routes` (8),
`FS-310-SMS-060` (7), `FS-370-SMS-120`, `FS-270-SMS-020`, `FS-800-*` (3 each).

Each must be re-read to decide whether it asserts the model (keep) or the
pipeline (rewrite). Two are already known:

- `test-upstream-selector-core-main-routes` was corrected in this run to assert
  per-interface; it is now truthful.
- `test-declaring-interface-keeps-its-route` becomes a hard assertion with
  expected count 0.

## What has been proven, so the next attempt need not re-derive it

- the emit path (`interface-units.nix` -> networkd) is confirmed by injection;
- the canonical data reaches that file when the chain is wired;
- the identity is the 5-part `(runtimeIfName, dst, gateway, tableId, metric)`,
  unique per target by construction;
- target scoping needs no parsing (`canonicalRuntimeTargets`);
- the emission is 20 lines and produces exactly the model's routes;
- `routeOutputInterface` alone accounts for 160 of 2,117, and removing it breaks
  `FS-540-SMS-040` -- so no partial deletion is a net win.

## What has been disproven, so it is not retried

De-duplicating by iteration order deletes the declaring route; de-duplicating by
own-table unmasks the placement defect; stamping tables in `raw-routes.nix`
changes nothing (that is not the installation path); filtering rendered routes
cannot work (10 of 363 overlap); matching on interface+destination matches
foreign targets; adding the gateway matches nothing (the gateway is rewritten
too: canonical `10.10.0.2` renders as `10.10.0.10`).
