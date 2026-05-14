# network-renderer-nixos regression state

Last updated: 2026-05-14.

## architecture shape

- state=required | target=s88-style Enterprise/Site/Unit/EquipmentModule/ControlModule layout | reason=renderer code must stay in s88-style responsibility folders; top-level files are limited to flakes, tests, scripts/entrypoints, and thin imports into the renderer structure.
- state=required | target=no oversized implementation files | reason=Nix implementation files over 200 LOC must be split by concrete renderer responsibility unless they are flake/test wiring or explicitly documented as a temporary regression with a split target.
- state=hard-fail | target=no repeated S88 role/site/name literals outside include routing | reason=role names (`access`, `policy`, `upstream-selector`, `downstream-selector`, `core`), role abbreviations, and lab/site literals (`esp0xdeadbeef`, `s-router`, `site-a`, etc.) are topology identity, not local renderer logic. They are acceptable when used to include the file that owns that structural slice, but using them in implementation expressions means a module is rediscovering S88 structure from names instead of receiving parsed Enterprise/Site/Unit/EquipmentModule/ControlModule data. That creates silent false matches when examples add new names or abbreviations, so the gate must hard-exit instead of warning.

## fixed and locally tested

- 2026-05-14 full-loop branch DNS validation reached
  `s-router-policy-only` on `up-cli-ew`; nftables had the explicit
  `up-cli-ew -> downstream-mgmt` DNS accept, but the `up-cli-ew` policy table
  lacked the route to `10.20.10.0/24`. Policy routing source discovery consumed
  `forwardingIntent.rules` but ignored the explicit CPM
  `normalizedExplicitForwardPairs` already used by firewall rendering. This is
  now covered by `tests/test-policy-routing-explicit-forward-pairs.sh`; full
  lab validation is still pending.
- 2026-05-14 live hostile delegated IPv6 public-egress debugging found
  `b-router-upstream-selector` accepted `pol-hostile-ew -> core-nebula` in
  nftables, but real packets were routed with `oif core-isp` and dropped
  because the policy table contained a projected ISP default. After replacing
  table 2004 with only the `core-nebula` default, replies looped on
  `core-nebula` until a main-table return route plus an earlier
  `iif pol-hostile-ew lookup 2004` rule were installed. The renderer now
  refuses to project default routes from non-target source interfaces into a
  policy table, and upstream-selector policy ingress rules consult the policy
  table before main-table fallback. Covered locally by
  `bash tests/test-dns-service-policy-routes.sh` and
  `bash tests/test-upstream-selector-core-main-routes.sh`; full lab validation
  is still pending.
- 2026-05-14 full-loop site-C DNS-over-overlay failed at
  `dig -b 10.70.10.1 @10.90.10.1`. Live tcpdump showed DNS requests left
  `b-router-access-hostile` but never reached `b-router-policy
  downstr-hostile`; `b-router-downstream-selector` allowed
  `access-hostile -> policy-hostile` in nftables but had no route in the
  `access-hostile` ingress table toward `policy-hostile`. The upstream-selector
  default-filter fix is now scoped only to upstream-selector policy ingress, so
  downstream-selector access ingress can still receive the paired policy
  interface's explicit `policyOnly` default route. Covered locally by
  `bash tests/test-downstream-selector-default-paths.sh` and rechecked with
  `bash tests/test-dns-service-policy-routes.sh`; full lab validation is still
  pending.
- 2026-05-14 live hostile delegated IPv6 public-egress debugging showed CPM now
  emits sourceFile-scoped `core-nebula -> core` forwarding intent for runtime
  routed prefixes. The renderer now preserves `sourceFiles` on explicit
  forwarding pairs, suppresses broad static nft accepts for those pairs, and
  installs a runtime nft rule from the delegated prefix file instead. Covered
  locally by `bash tests/test-dynamic-source-forwarding.sh`; full lab
  validation is still pending.
- 2026-05-14 live return-path debugging showed Hetzner `c-router-nebula-core`
  looped public replies back out `upstream` until the remote delegated prefix
  was installed on `nebula1`. A later full-loop run proved the previous generic
  NixOS renderer exception was wrong: it installed
  `2a01:4f9:c01f:4186::/64 dev overlay-west`, which won over the provider
  `nebula1` route and broke the return path. The renderer now blocks all
  overlay-provider delegated prefix route synthesis; provider-specific
  runtime routes belong in `network-renderer-nebula` or another provider
  renderer. Covered locally by `bash tests/test-dynamic-source-forwarding.sh`
  and `bash tests/test-overlay-delegated-prefix-boundary.sh`; full lab
  validation is still pending.
- Network pipeline contract audit found policy endpoint mapping still parsed
  generated p2p lane names (`--access-` / `--uplink-`) to select firewall
  interfaces. The mapper now consumes explicit CPM/NFM transit adjacency lane
  metadata (`lane`, `laneMeta`, `uplinks`) instead. Covered locally by
  `tests/test-policy-endpoint-no-generated-link-parsing.sh`; full live
  validation is still pending.
- Network pipeline contract audit found container policy-routing derived source
  interface sets by scanning rendered nftables text. The renderer now consumes
  explicit CPM `forwardingIntent.rules` only. Covered locally by
  `tests/test-container-policy-routing-no-rendered-firewall-parsing.sh`; full
  live validation is still pending.
- Network pipeline contract audit found container network interface view could
  recover lane/uplink semantics from rendered lane strings such as
  `uplink::...`. The renderer now uses structured CPM backingRef lane/uplink
  metadata. Covered by `tests/test-policy-endpoint-no-generated-link-parsing.sh`
  and `tests/test-policy-forward-default-paths.sh`; full live validation is
  still pending.
- Network pipeline contract audit found container policy-routing classes still
  classified selector/policy/core interfaces from rendered ifname prefixes such
  as `access-`, `policy-`, `upstream-`, and `overlay-`. Classification now uses
  structured CPM `backingRef.lane.kind` and `backingRef.kind`. Covered locally
  by `tests/test-policy-forward-default-paths.sh` and
  `tests/test-policy-cpm-firewall-parity.sh`; full live validation is still
  pending.
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
- DNS service source binding and public resolver output leak guard are locally
  covered by `bash tests/test-dns-local-records.sh`: the renderer consumes
  explicit `services.dns.outgoingInterfaces` as Unbound `outgoing-interface`
  values and emits nft output rules that accept DNS service egress only from
  modeled source addresses before dropping modeled public resolver CIDRs. The
  cross-site renderer test is updated for the same contract but needs the
  downstream lock to consume the CPM `outgoingInterfaces` output before it can
  pass through the locked chain.
- Upstream-selector policy-only IPv4 default projection is locally covered by
  `bash tests/test-policy-only-routes.sh`. The renderer now projects a
  `policyOnly` default from the matching upstream-selector core lane into the
  same-uplink policy-lane ingress table without installing it as a main-table
  default. This targets the live hostile symptom where
  `b-router-upstream-selector` needed table `2004` default via
  `core-nebula`.
- 2026-05-13 live enumeration captured NixOS-rendered endpoint/router nft
  posture across `s-router-test`, `s-router-test-clients`, and the Hetzner
  validator. The evidence is current but not yet a pass: direct
  `dig @1.1.1.1` is blocked from tested access routers and most endpoints, but
  succeeds from Hetzner `c-router-lighthouse`; endpoint firewalls commonly have
  input hook `policy accept`; some access routers have `deny-direct-dns-egress`
  rules while others do not. This needs focused renderer/CPM contract tests
  before any production-ready claim.
- 2026-05-13 fast visible-scope refresh captured
  `/tmp/s-router-fast-enum-20260513T212251Z/summary/fast.tsv` while Hetzner was
  down/not visible. It confirms direct public DNS remains blocked from
  endpoints and access routers, endpoint public egress is mixed by lane, and
  the host contexts leak over the home WAN and must not be counted as lab
  success. The concrete home public IPv4 must not enter `network-*` diffs.

## still broken

- 2026-05-14 live `s-router-test` + Hetzner enumeration found hostile IPv4
  public egress is not production-safe. Baseline `b-router-access-hostile`
  host-origin traffic selected `10.50.0.3` and died before public egress.
  Temporary live route fixes proved missing IPv4 policy-default projection in
  several rendered ingress tables:
  `b-router-upstream-selector` needed `table 2004 default via 10.50.0.4 dev
  core-nebula`, `b-router-core-nebula` needed `table 2002 default via
  100.96.10.3 dev nebula1`, and Hetzner `c-router-upstream-selector` needed
  `table 2001 default via 10.80.0.4 dev core`. The branch upstream-selector
  same-uplink core-to-policy-lane projection is fixed locally; the core-nebula
  and Hetzner-side defaults still need locked-chain/live validation and may
  require additional CPM/provider route ownership if not present in CPM output.
- The same live probe separated host-origin access-router traffic from
  tenant-origin hostile traffic. `b-router-access-hostile` shell pings source
  from `10.50.0.2`, while hostile tenant traffic should source
  `10.70.10.0/24`. Any durable fix/test must state which behavior is intended:
  host-origin diagnostics may need modeled management/router egress, but tenant
  hostile egress must preserve the hostile lane over `core-nebula`.
- After the temporary branch-side route fixes, branch packets reached
  `b-router-core-nebula` and were forwarded toward `nebula1`, but Hetzner
  `c-router-upstream-selector` counters still stayed at zero. Nebula logs on
  both ends showed repeated branch/Hetzner handshakes followed by
  `Tunnel status ... state:dead`; this is a second bug, not solved by nftables
  flushes. Check rendered Nebula runtime routes/certs/underlay reachability and
  add a focused renderer/runtime regression for live overlay health.
- 2026-05-14 Hetzner live enumeration found the public WAN core works while
  modeled access and Nebula paths do not. `c-router-core` can reach public IPv4
  and direct public DNS through `eth0`, and `c-router-nebula-core` works when
  sourced from `portforward`, but `c-router-nebula-core` fails via its modeled
  `upstream` path with `Destination Net Unreachable` from
  `c-router-upstream-selector` (`10.80.0.11`). That reproduces the missing
  policy-default problem for `core-nebula` ingress on the Hetzner side.
- 2026-05-14 endpoint enumeration from `s-router-test-clients` showed
  `hostile-node01` has the floating public IPv6 prefix
  `2a01:4f9:c01f:4186::/64`, but DNS, direct public DNS, public IPv4 ping/curl,
  and public IPv6 ping all fail. That means the allocator fix is consumed, but
  hostile egress is still blocked by route/policy/overlay behavior.
- 2026-05-14 endpoint enumeration showed direct public DNS remains blocked from
  tested endpoints, while `s-router-access-mgmt` and `c-router-lighthouse`
  router/container contexts can direct-DNS to `1.1.1.1`. Confirm whether this is
  intended management/lighthouse policy; otherwise add leak-prevention tests for
  those contexts.
- 2026-05-14 DNS service enumeration showed access routers are rendered with
  Kea DHCPv4, radvd RDNSS, and Unbound tenant listeners, while core routers
  have no Unbound or modeled DNS listener. Cores do not inherently need
  Kea/radvd, but if CPM emits an explicit core/service-node DNS listener target
  the renderer must materialize it without role-name or lab-topology inference.
- 2026-05-14 Hetzner live DNS probe showed `c-router-access-client` and
  `c-router-access-dmz` Unbound listeners are active, but local queries to
  loopback and tenant DNS addresses time out. The rendered Unbound configs have
  forwarders but no `outgoing-interface`, and route-get to those forwarders
  selects transit/p2p source addresses. First check whether CPM emits an
  explicit DNS outgoing/source contract; if it does, the renderer must preserve
  it, and if it does not this is upstream CPM/model ownership.
- 2026-05-14 00:58 UTC live refresh reproduced DNS failures on both
  `s-router-test` and Hetzner. `b-router-access-hostile`,
  `b-router-access-branch`, `c-router-access-client`, and
  `c-router-access-dmz` all have active Unbound listeners on loopback plus
  tenant DNS addresses and nft output accepts that allow DNS service egress
  only from tenant DNS source addresses. Foreground testing on
  `c-router-access-dmz` disproved the first renderer hypothesis: live
  `/etc/unbound/unbound.conf` already contains `outgoing-interface:
  10.90.10.1` and `outgoing-interface: fd42:dead:cafe:10::1`, and manually
  running Unbound with that binding still timed out. Direct
  `dig -b 10.90.10.1 @1.1.1.1`, `ping -I 10.90.10.1 1.1.1.1`, and
  source-bound traceroute also failed while reaching the policy/upstream/core
  path. The next renderer/CPM check is forwarding/NAT/firewall
  materialization and over-expanded accepted pairs, not Unbound source binding.
- The same live packet proof showed the query is NATed correctly at
  `c-router-core` and the public DNS reply is de-NATed back out the core's
  `upstream` interface toward `10.90.10.1`, but the reply was not observed on
  `c-router-policy`. The next owning-repo test should focus on
  upstream-selector return-path route/firewall materialization for site-C DMZ
  DNS egress, plus whether CPM or the renderer is producing the broad
  same-interface DNS/4242 accepts observed on `c-router-policy`.
- 2026-05-14 Hetzner `c-router-policy` rendered very broad repeated DNS and
  port-4242 accepts, including same-interface combinations such as
  `up-client-wan -> up-client-wan` and `up-dmz-wan -> up-dmz-wan`. Check
  whether CPM is emitting these accepted pairs or the renderer is over-expanding
  firewall relations; this may be too permissive for production.
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
  all runnable `network-labs` examples. This is temporary evidence only, not
  durable validation.
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
