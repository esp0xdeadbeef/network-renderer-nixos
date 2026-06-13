# network-renderer-nixos

`network-renderer-nixos` emits NixOS configuration from explicit
`network-control-plane-model` output.

It is an emission stage only.

Migration, deviation, exception, transition, or temporary compatibility behavior
must be explicit in the README, tests, and owning layer before it is accepted.

```text
network-forwarding-model -> network-control-plane-model -> network-renderer-nixos
```

## Spec Chain

This renderer is owned by the following GAMP trace chain. All behavior requirements
originate from the URS, flow through FS, and are refined by HDS → SDS → SMS before
reaching this renderer.

### Primary Chain: Renderer Policy Boundary

| Layer | ID | Description |
|-------|----|-------------|
| URS   | L11, L29, L156 | Portable meaning, renderers don't invent meaning, explicit policy only |
| FS    | FS-310 | Renderer Policy Boundary — materialize explicit CPM policy, no local allow rules |
| FS    | FS-320 | Renderer Layout Preservation — compact layouts must preserve roles/policy/hygiene |
| FS    | FS-982 | Host Configuration Renderer Boundary — NixOS host config stays thin; generated network realization belongs in renderers, not host profiles |
| HDS   | FS-310-HDS-010 | Renderer Policy Boundary hardware design — substrate facts for renderer contracts |
| SDS   | FS-310-HDS-010-SDS-010 | Renderer Policy Boundary software design — interface architecture, S88 layout, primitive registry |
| SMS   | FS-310-HDS-010-SDS-010-SMS-010 | **Coordinator** — renderer policy boundary module (SMT: OK) |
| SMS   | FS-310-HDS-010-SDS-010-SMS-040 | Interface name source binding — no hardcoded `eth0`/`ens3` |
| SMS   | FS-310-HDS-010-SDS-010-SMS-050 | nftables primitive source binding — table/chain names from CPM |
| SMS   | FS-310-HDS-010-SDS-010-SMS-100 | CPM-only consumption — no intent.nix, inventory.nix parsing |
| SMS   | FS-310-HDS-010-SDS-010-SMS-110 | Fail-closed contract — missing/partial CPM input must fail |
| SMS   | FS-310-HDS-010-SDS-010-SMS-120 | No naming inference — don't guess from node/interface/role names |
| SMS   | FS-310-HDS-010-SDS-010-SMS-130 | No policy invention — don't create firewall/routing from defaults |

### Secondary Chain: Layout Preservation

| Layer | ID | Description |
|-------|----|-------------|
| FS    | FS-320 | Renderer Layout Preservation — compact layouts must preserve roles/policy/hygiene |
| HDS   | FS-320-HDS-010 | Layout Preservation hardware design — substrate constraints for role co-location |
| SDS   | FS-320-HDS-010-SDS-010 | Layout Preservation software design — mapping logical roles without reinterpretation |
| SMS   | FS-320-HDS-010-SDS-010-SMS-010 | Coordinator — layout preservation module (SMT: OK) |
| SMS   | FS-320-HDS-010-SDS-010-SMS-020 | Runtime interface name mapping — deterministic valid names with audit alias |
| SMS   | FS-320-HDS-010-SDS-010-SMS-030 | Renderer interface audit mapping — inspectable logical-to-runtime mapping |

### SMT Status (2026-06-12)

- FS-310-HDS-010-SDS-010-SMS-010: **OK** — Coordinator: NixOS tests pass (policy-endpoint, container-routing, firewall-parity, explicit-forwarding)
- FS-320-HDS-010-SDS-010-SMS-010: **OK** — Coordinator: bridge-link realization contracts pass
- All child SMS rows trace to coordinator or are in controlled SMT backlog.

### Pipeline

```
network-labs (intent + inventory) → network-compiler → NFM → CPM → network-renderer-nixos
```

Required input: CPM output only. Must not parse `intent.nix`, `inventory.nix`, or `inventory-nixos.nix`.

### Owning Repository

Construction tests: `network-renderer-nixos/tests/`

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
- Map explicit logical interface identities to deterministic platform-valid
  runtime interface names where Linux-bound artifacts impose stricter limits,
  while preserving aliases for audit back to the CPM/provider identity.

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
- `lib.renderer.hostModule { outPath; hostName; ... }` for a NixOS module
  attrset carrying rendered networkd, container, module-argument and debug
  artifact output

## Tests

Run the repo-local tests before claiming conformance:

```bash
bash tests/test.sh
```

Use focused tests for touched behavior where available.
