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
- Added `tests/test-controlmodule-boundary.sh` to hard fail if ControlModule
  files import upward layers or if context-selecting entrypoints reappear under
  ControlModule.

## implemented but not yet live-validated

- Long logical realization port aliases are preserved into rendered container
  interfaces so firewall rules resolve to concrete Linux ifnames. This prevents
  `policy-client-wan` from leaking into nftables as an over-15-character
  interface name.
- Added `tests/test-container-firewall-ifname-limit.sh` for the site-c Hetzner
  upstream selector ruleset.

## still broken

- The repo still has many production `.nix` files over the 200-line structural
  guard. Normal `tests/test-passing-fixtures.sh` fails early on that guard until
  segmentation continues.

## next concrete debugging target

- Continue splitting large Unit/CM render files without moving decisions into
  ControlModules. Start with files listed by `tests/test-nix-file-loc.sh`.
