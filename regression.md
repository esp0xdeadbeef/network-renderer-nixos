# network-renderer-nixos regression state

Last updated: 2026-05-10.

## architecture shape

- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=renderer code must stay in s88-style responsibility folders; top-level files are limited to flakes, tests, scripts/entrypoints, and thin imports into the renderer structure.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete renderer responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.
- state=hard-fail | target=no repeated S88 role/site/name literals outside include routing | reason=role names (`access`, `policy`, `upstream-selector`, `downstream-selector`, `core`), role abbreviations, and lab/site literals (`esp0xdeadbeef`, `s-router`, `site-a`, etc.) are topology identity, not local renderer logic. They are acceptable when used to include the file that owns that structural slice, but using them in implementation expressions means a module is rediscovering S88 structure from names instead of receiving parsed Enterprise/Site/Unit/EquipmentModule/ControlModule data. That creates silent false matches when examples add new names or abbreviations, so the gate must hard-exit instead of warning.

## fixed and locally tested

- Downstream selectors now preserve explicit CPM `policyOnly` default routes
  from the paired `policy-*` interface into the `access-*` ingress policy
  table. This fixes the live failure where access traffic reached the
  downstream selector and died before the policy router even though CPM had
  modeled the policy-side default route. Covered by
  `tests/test-downstream-selector-default-paths.sh`.
- Policy-router ingress tables now include service/tenant routes required by
  explicit accepted forwarding pairs from the rendered CPM-backed nft contract.
  This fixes the live site-c DNS failure where `c-router-policy` allowed
  `up-client-ew -> downstream-dmz` DNS, but the `up-client-ew` policy table had
  no route to the DMZ DNS service. Covered by
  `tests/test-policy-service-ingress-routes.sh`.
- `tests/test-passing-fixtures.sh` passed on 2026-05-10 after the downstream
  selector and policy service-ingress route fixes.
- ControlModule boundary is explicit: `s88/ControlModule` must not import or
  execute `s88/Unit`, `s88/EquipmentModule`, or `s88/Site` code.
- Unit owns host/runtime selection: deciding which runtime units and containers
  belong to a requested deployment host is Unit-level work.
- Equipment owns host equipment composition: deciding which ControlModules are
  required for a selected host, such as host networking, container runtime, and
  validation, is Equipment-level work.
- ControlModules own deterministic rendering of the narrowed slice they are
  given. They must not ask broad host/site/unit questions to decide whether the
  work applies.
- Boundary checks are covered by `tests/test-controlmodule-boundary.sh`,
  `tests/test-s88-call-flow.sh`, and `tests/test-s88-call-flow-profiler.sh`.
  These are local renderer tests only; they do not prove live host behavior.
- Structural keyword leakage is covered by
  `tests/test-s88-structural-keyword-warnings.sh`. Role profile lookup now
  lives in Unit and is derived from owned profile files; ControlModule receives
  parsed role behavior such as profile paths, firewall policy paths, assumption
  families, and feature flags instead of comparing runtime role literals.
  The test hard-fails if role/site/name literals return outside include/import
  routing.
- Clean renderer outputs must not contain warnings or alarms. This is covered by
  `tests/test-warning-alarm-contract.sh` and by the passing fixture runners.
- Renderer warning/error behavior is not allowed to be silent:
  `tests/test-warning-alarm-contract.sh` proves synthetic warnings surface as
  NixOS `evaluation warning:` output, and missing renderer inputs fail hard.
- DNS service rendering preserves explicit `dnsService.outgoingInterfaces` and
  otherwise derives Unbound outbound source addresses from the DNS listener
  addresses. This keeps access-router forwarding traffic on the modeled DNS
  service lane instead of leaking router p2p or WAN source addresses into DNS
  policy.

## implemented but not yet live-validated

- Long logical realization port aliases are preserved into rendered container
  interfaces so firewall rules resolve to concrete Linux ifnames. This prevents
  over-15-character logical names from leaking into nftables.
- The DNS outbound source-address correction is locally covered by
  `tests/test-dns-local-records.sh`, `tests/test-dual-wan-branch-overlay.sh`,
  and `tests/test-hostile-dns-east-west.sh`.
- No live `s-router-test`, `s-router-test-clients`, or Hetzner runtime
  validation has been completed for the DNS source-address change in this
  renderer entry. Treat the current state as locally tested, not
  production-ready.

## still broken

- `tests/test-nix-file-loc.sh` reports by layer and hard-fails only over
  500 LOC by default. Files over 250 LOC must state either
  `TEMPORARY OVER-LIMIT` or `ACCEPTED OVER-LIMIT`.
- `s88/ControlModule/lookup/host-query/inventory.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: builds the host inventory query adapter.
  Suspected split: inventory shape normalization vs host matching.
- `s88/ControlModule/firewall/lookup/assumptions.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: collects firewall assumption alarms.
  Suspected split: assumption discovery vs alarm grouping/formatting.
- `s88/ControlModule/render/dry-config-model.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: assembles the dry render debug model.
  Suspected split: host/container mapping vs debug output shaping.
- `s88/ControlModule/alarm/isa18.nix`: ACCEPTED OVER-LIMIT FOR NOW.
  Current responsibility: defines ISA-18 alarm vocabulary and formatting.
  Reason kept: mostly declarative alarm structure.
  Revisit if formatting and policy classification diverge.
- `s88/ControlModule/render/containers/bgp-services.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: renders BGP container services.
  Suspected split: service config assembly vs validation.
- `s88/ControlModule/render/containers/default.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: composes container render modules.
  Suspected split: service assembly vs module selection.
- `s88/ControlModule/firewall/lookup/communication-contract.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: resolves firewall communication contracts.
  Suspected split: relation parsing vs endpoint mapping.
- `s88/Unit/physical/realization-ports/inventory.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: adapts Unit realization-port inventory.
  Suspected split: inventory parsing vs attach identity extraction.
- `s88/ControlModule/firewall/policy/access.nix`: TEMPORARY OVER-LIMIT until 2026-05-17.
  Current responsibility: renders access firewall policy.
  Suspected split: endpoint classification vs rule assembly.

## network-labs output-analysis backlog

State: NOT DONE.

Do not treat "the example rendered" as proof that the renderer output is
correct. Each input below must be analyzed one by one from the full dry render
output, using compact JSON (`jq -c .`) as the starting artifact. Only after the
actual output shape is understood should a regression test be written.

For every input:

- Compile `intent.nix` with the NixOS inventory used by the existing external
  example path. If the directory has `getResolvedInventory.nix`, use it before
  compiling.
- Save and inspect the full `90-dry-config.json` through `jq -c .`.
- Check output-owned evidence, not source-file assumptions:
  rendered hosts, rendered nodes, rendered containers, rendered sites, host
  network fragments, container firewall/routing/services, debug source paths,
  and warning/alarm/error-shaped fields.
- Write a focused test only after the output inspection identifies the contract
  implied by the example name.

Current status:

- Raw compact outputs were generated during the 2026-05-06 investigation for
  all 23 runnable `network-labs` inputs, including the `lab-s-sigma` resolved
  inventory path. This is temporary evidence only, not durable validation.
- High-level counts were sampled, but full semantic review was NOT completed.
- The output-focused test changes from the same investigation are provisional
  until the per-input review below is completed.

Per-input backlog:

- `examples/single-wan`: NOT DONE. Test the baseline single-WAN output: one
  WAN uplink, default reachability, tenant access routing, policy path, and no
  extra overlay/BGP/VLAN/service behavior.
- `examples/single-wan-any-to-any-fw`: NOT DONE. Test that the firewall output
  permits the modeled any-to-any relation without replacing it with broad
  accidental accepts or missing tenant/interface scoping.
- `examples/single-wan-bgp`: NOT DONE. Test BGP service output for the simple
  single-WAN case: daemon enablement, AS/neighbor/network statements, and
  placement on the intended containers.
- `examples/single-wan-direct-transit`: NOT DONE. Test direct transit output:
  transit links and routes should bypass selector-only assumptions while still
  rendering complete host/container network fragments.
- `examples/single-wan-ipv6-pd`: NOT DONE. Test IPv6-PD output: delegated
  prefix consumption, downstream RA/DHCPv6 behavior, and absence of renderer
  default-derived warning alarms.
- `examples/single-wan-uplink-ebgp`: NOT DONE. Test eBGP uplink output:
  external neighbor configuration, route advertisement, and uplink interface
  placement.
- `examples/single-wan-uplink-static-egress`: NOT DONE. Test static egress
  output: explicit default/static routes, gateway placement, and policy rules
  tied to the modeled uplink.
- `examples/single-wan-vlan-trunk-lanes`: NOT DONE. Test VLAN trunk output:
  VLAN netdevs, bridge/network fragments, DHCP/RA behavior, and lane separation.
- `examples/single-wan-with-nebula`: NOT DONE. Test overlay output without
  making this renderer infer Nebula semantics from names: rendered overlay
  interfaces/routes must come from explicit CPM/provider-neutral data.
- `examples/single-wan-with-nebula-any-to-any-fw`: NOT DONE. Test that overlay
  plus any-to-any firewall output keeps tenant/overlay/WAN scoping explicit and
  does not emit broad unqualified accepts.
- `examples/multi-wan`: NOT DONE. Test multi-WAN output: distinct uplinks,
  selector/policy behavior, per-uplink routes, and no collapsed single-WAN
  assumptions.
- `examples/multi-wan-dedicated-lanes`: NOT DONE. Test dedicated-lane output:
  separate policy lanes per access/uplink combination and no cross-lane leakage.
- `examples/multi-enterprise`: NOT DONE. Test enterprise/site disambiguation:
  duplicate logical node names across enterprises must render distinct
  containers, nodes, policies, and host fragments.
- `examples/overlay-east-west`: NOT DONE. Test east-west overlay output:
  inter-site routes, overlay attachment interfaces, and firewall/policy rules
  for east-west traffic only.
- `examples/priority-stability`: NOT DONE. Test deterministic ordering:
  firewall/routing/service priority output should remain stable and not depend
  on attrset traversal order.
- `examples/ipv6-pd-downstream-delegation`: NOT DONE. Test downstream
  delegated-prefix output: the required example must expose the delegated
  prefix through rendered advertisements and validation artifacts.
- `examples/dual-wan-branch-overlay`: NOT DONE. Test dual-WAN branch overlay
  output: WAN split, branch overlay routes, service forwarding, DNS policy, and
  no cross-uplink policy leakage.
- `examples/dual-wan-branch-overlay-bgp`: NOT DONE. Test the same dual-WAN
  branch overlay shape plus BGP service output and route advertisement.
- `examples/s-router-overlay-dns-lane-policy`: NOT DONE. Test the full
  s-router output: DNS lane preservation, policy lane routes, multi-host
  container placement, overlay routes, and service firewall rules.
- `examples/s-router-public-overlay-service`: NOT DONE. Test public overlay
  service output: DNAT/public ingress, runtime public address loading, overlay
  service firewall rules, and host policy routing.
- `examples/tri-site-dual-wan-overlay-integration-static`: NOT DONE. Test
  tri-site static integration output: all site renderings, dual-WAN separation,
  static overlay reachability, and complete per-site containers.
- `examples/tri-site-dual-wan-overlay-integration-bgp`: NOT DONE. Test tri-site
  BGP integration output: the static integration shape plus BGP daemon and
  route advertisement correctness.
- `labs/lab-s-sigma/s-router-test-three-site`: NOT DONE. Test the resolved
  inventory path explicitly: `getResolvedInventory.nix` must be used, and the
  rendered output must match the real s-router three-site host/container
  contract rather than the unresolved inventory placeholders.

## next concrete debugging target

- Work through the network-labs output-analysis backlog one input at a time.
  Do not mark an input complete until the full compact output has been inspected
  and the resulting regression test asserts the actual rendered output contract.
- Before 2026-05-17, either split every `TEMPORARY OVER-LIMIT` file by the
  suspected responsibility split above, or replace the temporary marker with a
  real accepted-over-limit reason.
- After local tests are green, run live validation for `s-router-test`,
  `s-router-test-clients`, and the Hetzner site-c path before calling the
  renderer production-ready.
