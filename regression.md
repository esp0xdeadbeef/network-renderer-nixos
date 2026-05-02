# network-renderer-nixos regression state

Last updated: 2026-05-02.

## fixed and locally tested

- ControlModule boundary is now explicit: `s88/ControlModule` must not import or
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
- Clean renderer outputs must not contain warnings or alarms. This is covered by
  `tests/test-warning-alarm-contract.sh` and by the passing fixture runners.
- Renderer warning/error behavior is not allowed to be silent:
  `tests/test-warning-alarm-contract.sh` proves synthetic warnings surface as
  NixOS `evaluation warning:` output, and missing renderer inputs fail hard.
- `s-router-test-clients` must retain the Chromecast/client `streaming` VLAN
  311. `tests/test-host-uplink-vlan-dhcp.sh` checks the locked
  `network-labs` fixture renders that bridge on the clients host.

## implemented but not yet live-validated

- Long logical realization port aliases are preserved into rendered container
  interfaces so firewall rules resolve to concrete Linux ifnames. This prevents
  `policy-client-wan` from leaking into nftables as an over-15-character
  interface name.
- Added `tests/test-container-firewall-ifname-limit.sh` for the site-c Hetzner
  upstream selector ruleset.
- No live `s-router-test`, `s-router-test-clients`, or Hetzner runtime
  validation has been completed for this renderer change set in this entry.
  Treat the current state as locally tested, not production-ready.

## still broken

- `tests/test-nix-file-loc.sh` now reports by layer and hard-fails only over
  500 LOC by default. Files over 250 LOC must state either
  `TEMPORARY OVER-LIMIT` or `ACCEPTED OVER-LIMIT`.
- `s88/ControlModule/lookup/host-query/inventory.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: builds the host inventory query adapter.
  Suspected split: inventory shape normalization vs host matching.
- `s88/ControlModule/firewall/lookup/assumptions.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: collects firewall assumption alarms.
  Suspected split: assumption discovery vs alarm grouping/formatting.
- `s88/ControlModule/render/dry-config-model.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: assembles the dry render debug model.
  Suspected split: host/container mapping vs debug output shaping.
- `s88/ControlModule/alarm/isa18.nix`: ACCEPTED OVER-LIMIT FOR NOW.
  Current responsibility: defines ISA-18 alarm vocabulary and formatting.
  Reason kept: mostly declarative alarm structure.
  Revisit if formatting and policy classification diverge.
- `s88/ControlModule/render/containers/bgp-services.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: renders BGP container services.
  Suspected split: service config assembly vs validation.
- `s88/ControlModule/render/containers/default.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: composes container render modules.
  Suspected split: service assembly vs module selection.
- `s88/ControlModule/firewall/lookup/communication-contract.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: resolves firewall communication
  contracts. Suspected split: relation parsing vs endpoint mapping.
- `s88/Unit/physical/realization-ports/inventory.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: adapts Unit realization-port inventory.
  Suspected split: inventory parsing vs attach identity extraction.
- `s88/ControlModule/firewall/policy/access.nix`: TEMPORARY OVER-LIMIT until 2026-05-09.
  Current responsibility: renders access firewall policy.
  Suspected split: endpoint classification vs rule assembly.

## next concrete debugging target

- Before 2026-05-09, either split every `TEMPORARY OVER-LIMIT` file by the
  suspected responsibility split above, or replace the temporary marker with a
  real accepted-over-limit reason.
- After local tests are green, run live validation for `s-router-test`,
  `s-router-test-clients`, and the Hetzner site-c path before calling the
  renderer production-ready.
