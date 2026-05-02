# network-renderer-nixos

`network-renderer-nixos` emits NixOS configuration from explicit
`network-control-plane-model` output.

It is an emission stage only.

```text
network-forwarding-model -> network-control-plane-model -> network-renderer-nixos
```

## Contract

- The forwarding model and CPM are the source of truth.
- This renderer consumes resolved CPM output and emits NixOS-shaped artifacts.
- Runtime renderer behavior must be derived from CPM output only, not from
  `intent.nix`, `inventory.nix`, `inventory-nixos.nix`, or repository-local
  source parsing.
- Missing, partial, or inconsistent input must fail evaluation.
- Renderer output must be deterministic for the same CPM input.
- Rendered debug/artifact files must expose the consumed inputs and emitted
  host/container shape for audit.

## Allowed

- Map CPM interfaces, addresses, routes, rules, services, and host/container
  selections into NixOS module fragments.
- Emit systemd-networkd, nftables, resolver, DHCP/RA, service, and validation
  configuration from explicit CPM fields.
- Consume explicit provider-neutral overlay interface semantics supplied by CPM
  or a provider renderer.

## Not Allowed

- Invent topology, forwarding, policy, tenant, uplink, overlay, or DNS meaning.
- Guess behavior from node names, interface names, role names, or string tokens.
- Treat a provider name such as `nebula`, `wireguard`, or `openvpn` as generic
  forwarding truth.
- Repair missing CPM fields with local defaults.
- Reinterpret inventory, intent files, or examples as hidden forwarding
  authority.
- Move provider-specific runtime materialization into this renderer.

## Test Boundary

Renderer tests may load `intent.nix` and inventory files to build the upstream
pipeline and assert that renderer output preserves the expected contract. That
is test scaffolding only.

Production renderer code must not parse those files for meaning. If a renderer
needs a concept such as lane identity, overlay transport semantics, WAN
eligibility, delegated-prefix sources, DNS policy, or firewall behavior, that
concept must be explicit in CPM output. Missing CPM data is an upstream contract
bug, not a renderer inference opportunity.

## Provider Boundary

Provider-specific runtime rendering belongs in the provider renderer.

Examples:

- Nebula profiles, lighthouses, unsafe routes, cert material, and daemon config
  belong in `network-renderer-nebula`.
- WireGuard peer/key/interface runtime would belong in a WireGuard renderer.
- OpenVPN runtime would belong in an OpenVPN renderer.

This renderer may consume the resulting explicit NixOS module fragments or
provider-neutral interface semantics. It must not hardcode provider names to
derive routing, firewall, WAN eligibility, or overlay behavior.

## API

The flake exports NixOS-oriented helpers under `lib` and `libBySystem`.

Main consumers use:

- `lib.containers.buildForBox`
- `lib.hosts.buildHostFromPaths`
- renderer-produced host/container modules and debug artifacts

## Tests

Run the repo-local tests before claiming conformance:

```bash
bash tests/test-passing-fixtures.sh
```

Use focused tests for touched behavior where available.
