# BUG: the renderer withholds two published lane occurrences

Row: FS-310-HDS-020-SDS-010-SMS-060 (canonical SMS slug
`renderer-route-command-source-binding`), mirrored at
`network-labs/GAMP/SMS/FS-310-HDS-020-SDS-010-SMS-060/`.

Status: OPEN, filed 2026-11-25. Found while reviewing
`network-control-plane-model` 9155d82 ("publish policyRoutingSources and
networkBehavior"), which is the producer half of this row's repair.

## The clause

FS-310-HDS-020-SDS-010-SMS-060 states, verbatim:

> Install each canonical route into exactly the context table and lane the
> canonical record names. The renderer shall not choose, infer, or withhold a
> route's table or lane occurrence: it shall not gate a route's materialization on
> the presence of a forwarding rule, derive occurrence from interface topology, or
> rely on an environment-supplied fallback table.

The failure condition this report is filed under is the third verb: **withhold**.

## Symptom

The model now publishes the lane occurrence for every runtime target, and the
renderer discards part of it. It does not fail, and it does not warn: the value
the renderer uses is its own derivation, not the model's record.

## Measurement

Realised from `network-labs/examples/wireguard-provider-overlay`, reading the
model's record and the value the renderer's mapping produces for the same target.
Run from a checkout that has `network-labs` and `network-control-plane-model` as
siblings of this repository:

```nix
# measure-withheld.nix
let
  flake = builtins.getFlake ("path:" + toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  mapping = import (./. + "/s88/Unit/mapping/runtime-targets.nix") { inherit lib; };
  ex = flake.inputs.network-labs + "/examples/wireguard-provider-overlay";
  cpm = flake.inputs.network-control-plane-model.lib."x86_64-linux".compileAndBuildFromPaths {
    inputPath = "${ex}/intent.nix";
    inventoryPath = "${ex}/inventory-nixos.nix";
  };
  modelTarget =
    cpm.control_plane_model.data.esp0xdeadbeef.site-a.runtimeTargets
      .esp0xdeadbeef-site-a-s-router-core-nebula;
  mapped = mapping.normalizedRuntimeTargets { inherit cpm; file = "measure-withheld.nix"; };
  mappedTarget = mapped."esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-s-router-core-nebula";
  kept = [ "isSelector" "isUpstreamSelector" "isPolicy" "isAccessGateway" "keepInterfaceRoutesInMain" ];
in
{
  inherit (modelTarget) policyRoutingSources;
  rendererPolicyRoutingSources = mappedTarget.policyRoutingSources;
  modelSourcesWithheld = builtins.filter
    (name: !(mappedTarget.policyRoutingSources ? ${name}))
    (builtins.attrNames modelTarget.policyRoutingSources);
  behaviorKeysDropped = builtins.filter
    (k: !(mappedTarget.networkBehavior ? ${k}))
    (builtins.attrNames modelTarget.networkBehavior);
  fiveClassKeysAgree = builtins.all
    (k: (modelTarget.networkBehavior.${k} or null) == (mappedTarget.networkBehavior.${k} or null))
    kept;
}
```

```
nix eval --impure --json -f measure-withheld.nix
{"policyRoutingSources":{
   "ens3":["p2p-s-router-core-nebula-s-router-upstream-selector"],
   "overlay-nebula":["overlay-nebula"],
   "overlay-wg-egress":["overlay-wg-egress"]},
 "rendererPolicyRoutingSources":{
   "ens3":["p2p-s-router-core-nebula-s-router-upstream-selector"]},
 "modelSourcesWithheld":["overlay-nebula","overlay-wg-egress"],
 "behaviorKeysDropped":["enforcement","exit","participates","role","upstreamSelection"],
 "fiveClassKeysAgree":true}
```

The target is `esp0xdeadbeef::site-a::esp0xdeadbeef-site-a-s-router-core-nebula`.
The model names three policy sources; the renderer's mapping keeps one and
withholds `overlay-nebula` and `overlay-wg-egress`. `fiveClassKeysAgree: true`
is the control: the two records do not differ in the keys the renderer keeps, so
the disagreement is not a value drift, it is the narrower record replacing the
wider one.


The reproduction expression is deliberately small: it imports
`s88/Unit/mapping/runtime-targets.nix`, realises the example through
`network-control-plane-model`, and prints the model's `policyRoutingSources` next
to the mapped target's. Nothing in it asserts a value; it reports both.

Across three examples (`wireguard-provider-overlay`,
`s-router-overlay-dns-lane-policy`, `multi-enterprise`) the same holds:

- every runtime target carries both fields in the model (8, 26 and 14 targets);
- the five class keys the renderer keeps agree with the model everywhere, so the
  model's publication is a faithful move of the same predicate;
- `policyRoutingSources` agrees on all but one target per example, and where it
  disagrees the model's answer is a **superset**: the renderer's derivation omits
  source interfaces the model names (measured: `overlay-nebula` and
  `overlay-wg-egress` on the core);
- five `networkBehavior` keys the model publishes
  (`enforcement`, `exit`, `participates`, `role`, `upstreamSelection`) never
  reach the renderer at all.

## Where it happens

`s88/Unit/mapping/runtime-targets/default.nix`, `normalizedRuntimeTargetForUnit`:

```nix
runtimeTarget
// {
  interfaces = normalizedInterfaces;
  policyRoutingSources = interfaces.policyRoutingSources normalizedInterfaces;
  networkBehavior = interfaces.networkBehavior normalizedInterfaces;
  ...
}
```

The `//` operator is the defect: everything the model published is replaced by a
renderer-computed value. `requireModelFact` in the same file (added for this row)
checks that the model carries the field and then the merge discards it, so the
check passes while the renderer still decides.

`policyRoutingSources` is consumed by
`s88/ControlModule/render/container-networks/policy-routing/source-interfaces.nix`
(`unitSourcesRaw = policyRoutingSources.${targetName} or null`), and
`networkBehavior` by `s88/ControlModule/render/container-networks/classes.nix`
(`isSelector`, `isPolicy`, `isUpstreamSelector`, `isAccessGateway`,
`keepInterfaceRoutesInMain`). Both read the mapped value, i.e. the derivation.

## Why it is filed rather than fixed here

Deleting the derivation changes what the core installs. The model names policy
sources on two overlay interfaces the renderer currently leaves out, and the row
requires that the canonical record decides occurrence -- but "the model says so"
is not evidence that the rest of the route set still agrees, and the two
overlays are exactly the interfaces whose defaults this renderer had to repair in
the past (the 2026-11-21 duplicate-default failure this row was written after).

So there are two defensible orders and both need this row's own validation run:

1. delete `policyRoutingSources`/`networkBehavior` from the merge, consume the
   model's fields, and accept whatever the core's rendered route set becomes;
2. keep the merge until the canonical `canonicalRoutes` comparison covers the
   overlay lanes, then delete it in one change with the evidence.

Guessing (1) while the row's placement test is still red
(`tests/FS-310-HDS-020-SDS-010-SMS-060.sh`) would make a second, silent change
to the same lane at the same time as the first. Filed, not guessed.

## What would close it

- `normalizedRuntimeTargetForUnit` no longer computes either field: it passes the
  model's record through, and `requireModelFact` stays as the guarantee that the
  model supplied it.
- `tests/test-no-model-fact-derivation.sh` (or the row's own case) fails if the
  mapping ever computes `policyRoutingSources`/`networkBehavior` again.
- The row's placement case shows no new disagreement between a rendered route's
  place and the canonical record's place, on the examples that carry overlays.
- This file is deleted, with the closing commit cited in it.
