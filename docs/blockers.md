# Remaining renderer reds and their owner

Status: BLOCKED for the two tri-site cases and the legacy runtime-origin case;
the policy-table parity case is fixed.

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
- `tests/test-policy-cpm-firewall-parity.sh` is FIXED: control plane
  `c2cb1dc…2c7d382` copies each modeled accept rule's egress default into the
  ingress lane (tagged with the ingress lane, deduplicated, access lanes only),
  and the case now asserts the kernel table carries the default rather than
  which network renders it (FS-315).
- `tests/test-runtime-origin-loopback-egress-render.sh`: the main-table leak is
  fixed (`wrongPolicyRuntimeSourceMainRoutes: []`). The remaining flags
  (`hasCoreADefault`, `hasPolicyClientDefault`, `has*RuntimeSourceRule`,
  `runtimeOriginHasAccessOrigin`) assert an older topology that the fixture no
  longer models: it expects `up-client-b` and `pol-client-a/-b` lanes and a core
  runtime-origin prefix `10.19.0.8/32`, while the fixture models `up-cli-ew`,
  `up-client-a` and the tenant DNS origin prefixes. Migrating it needs the same
  authoritative tri-site replacement fixture as the two cases above.
