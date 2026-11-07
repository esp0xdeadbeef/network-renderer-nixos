# Remaining renderer reds and their owner

Status: BLOCKED for two cases. Both need a decision at the owning layer (an
authoritative tri-site example, and the runtime-origin egress lane contract),
not a renderer-side assertion that re-states the superseded topology.

## FIXED: `tests/test-transit-endpoint-return-routes.sh`

Both halves now pass.

- The `dual-wan-branch-overlay-bgp` fixture models the overlay participant
  endpoint identities the forwarding model needs for its peer next hop
  (FS-460: a `proto = overlay` route carries the peer overlay next hop and fails
  closed otherwise), scopes the overlay-underlay egress relation to the WAN exit
  core (`E_TRAFFIC_PATH_EXTERNAL_CORE_LOOP`), and declares the access selections
  the fixture already realizes (FS-322/FS-481: the lane set is the selection).
- The `s-router-overlay-dns-lane-policy` half asserted a generic default and an
  underlay return for the remote hostile prefix on the overlay core. That is the
  fail-open behavior FS-315 removed: a generic default is installed only on a
  lane whose modeled uplink offers one, so the overlay core's only defaults are
  the FS-460 policy-only delegated public-egress complements, and the delegated
  hostile prefix returns over the modeled policy lane toward the hostile access
  node (FS-550) instead of as an underlay default route. The case asserts that
  contract (including the absence of a main-table generic default) instead.

## BLOCKED: `tests/test-overlay-core-local-hostile-return-routes.sh`

Consumes `tests/fixtures/tri-site-s-router-overlay-egress`, which predates the
current compiler contracts: no `selects` on the access scopes (FS-322), no
overlay `peerNodes` endpoint identity (FS-460/URS overlay transport), and the
overlay is modeled as a routed core uplink that carries specific prefixes.
Adding the missing `selects` and `peerNodes` moves the failure to the next stale
assumption each time; the remaining one is the overlay-as-core-uplink modeling
(`overlay-core-uplink-dedicated`: "an overlay must not be modelled as a routed
core uplink that carries specific prefixes"). Migrating it means re-expressing
the imported prefixes as `transport.overlays.<name>.prefixes.imported` and
re-deriving the host inventory's overlay lane ports, i.e. authoring a canonical
tri-site example rather than editing the private copy. The attempted migration
is captured (not committed) and was reverted rather than left half-applied.

## BLOCKED: `tests/test-runtime-origin-loopback-egress-render.sh`

The main-table leak is fixed (`wrongPolicyRuntimeSourceMainRoutes: []`). The
remaining flags (`hasCoreADefault`, `hasPolicyClientDefault`,
`has*RuntimeSourceRule`, `runtimeOriginHasAccessOrigin`) assert the pre-FS-315
model in which the overlay core installed a generic default with
`PreferredSource` for the router loopback. In the current model:

- the runtime-origin source rule is rendered on the overlay core ingress
  (`iif = core-nebula`) and points at that lane's table (the overlay lane), while
  the modeled egress defaults live in the per-access underlay lane tables;
- the overlay core itself has no main-table default (FS-315, deliberately);
- the policy target's routes for the loopback source are policy-table scoped
  (FS-315/FS-550), not main-table.

Whether the runtime-origin source selector must be bound to the *egress* lane
table (so a loopback-origin packet selects the modeled underlay default) or the
overlay ingress lane table is a control-plane modeling decision (FS-550
route-selection authority), not a renderer assertion. The renderer cannot pick a
table the CPM did not model (`FS-310-HDS-010-SDS-010-SMS-130`: route table IDs
and priorities come from the CPM). The case stays red until the owning FS/CPM
decision lands; its assertions then follow that contract the same way the
transit case above does.
