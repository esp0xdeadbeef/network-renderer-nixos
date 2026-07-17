# Regression Notes

Keep this file current with solved or intentionally accepted repository-local
test-gate findings. Unresolved implementation defects should name the failing
command, evidence, owner, and next fix.

- `s88/ControlModule/render/container-networks/interface-units.nix`: ACCEPTED OVER-LIMIT. Single responsibility: emits container interface systemd network units from explicit runtime interface records. Splitting would scatter shared ordering and naming invariants across smaller files.
- `s88/ControlModule/render/container-networks/policy-routing/raw-routes.nix`: ACCEPTED OVER-LIMIT. Single responsibility: normalizes raw policy-route records for renderer emission. Splitting would separate common validation from route-shape handling.
- state=fixed-locally | target=s88/ControlModule/render/systemd-host-network/local-bridges.nix host bridge addresses | evidence=NETWORK_REPO_DIRECT_TEST_OK=1 bash tests/test-fs310-hds020-sds010-sms200-nixos-bridge-no-default.sh | reason=NixOS renderer must not assign hardcoded 10.11.0.1/24 to CPM/runtime bridges absent explicit bridgeNetworks.hostAddresses, DHCP, or SLAAC authority.
- state=open | target=kea-dhcp6 runtime server DUID state | evidence=2026-07-17 live FS-970 enrollment on s-router-nixos client-edge: kea-dhcp6-client.service exits with DHCP6_CONFIG_LOAD_FAIL because /var/lib/kea/kea-dhcp6-serverid cannot be opened for writing | reason=the standalone DHCPv6 unit declares RuntimeDirectory=kea but no writable StateDirectory for Kea's server identifier; owner is s88/ControlModule/access/render/kea-dhcp6.nix and recovery requires a focused unit contract test plus a live active service after rebuild.
