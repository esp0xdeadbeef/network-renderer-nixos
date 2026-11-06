# Remaining renderer reds and their owner

Status: BLOCKED for the two tri-site cases; the other reds are contract work in
progress.

- `tests/test-overlay-core-local-hostile-return-routes.sh` and
  `tests/test-transit-endpoint-return-routes.sh` consume the private fixture
  `tests/fixtures/tri-site-s-router-overlay-egress`. That fixture predates the
  current compiler contracts: it has no `selects` on access scopes (FS-322), no
  overlay `peerNodes` endpoint identity (FS-460/URS overlay transport), and it
  models the overlay name as a routed core uplink with specific prefixes
  (E_OVERLAY_UNDERLAY_ACCESS_WAN_EGRESS_REQUIRED / E_TRAFFIC_PATH_EXTERNAL_CORE_LOOP
  / overlay-uplink-prefix diagnostics). A partial migration was attempted and
  reverted rather than left half-applied.
  The correct source is a canonical tri-site example in `network-labs` with the
  host inventory this renderer needs. `network-labs` currently has no tri-site
  overlay example (`overlay-east-west`, `s-router-overlay-dns-lane-policy` and
  `s-router-public-overlay-service` only), and the forwarding model's tri-site
  fixture is intent-only. Until that canonical example exists, the renderer
  cannot derive the fixture from an authoritative source; hand-editing the
  private copy would re-create the drift this repository is trying to remove.
- `tests/test-policy-cpm-firewall-parity.sh` needs the per-ingress policy table
  to carry the selected exit default for the accepted forward flow. FS-315
  requires the ingress table, forward path and return path to share one modeled
  owner/lane; the canonical record currently carries the exit default on the
  egress lane only, and there is no modeled ingress-table relation to copy. That
  relation must be specified before it is emitted (FS-171 single writer), so it
  is not invented here.
- `tests/test-runtime-origin-loopback-egress-render.sh`: the remaining flags
  (`hasCoreADefault`, `hasPolicyClientDefault`, `has*RuntimeSourceRule`,
  `runtimeOriginHasAccessOrigin`) are the same ingress-table/selector-side
  defaults; the main-table leak (`wrongPolicyRuntimeSourceMainRoutes`) is fixed.
