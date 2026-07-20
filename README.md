# network-renderer-nixos

`network-renderer-nixos` emits NixOS configuration from one validated canonical
network-realization bundle and, when required, one validated NixOS platform-
binding bundle.

It is an emission stage only.

Migration, deviation, exception, transition, or temporary compatibility behavior
must be explicit in the README, tests, and owning layer before it is accepted.

```text
network-control-plane-model -> network-realization-model -> schema validation -> network-renderer-nixos
```

## Spec Chain

This renderer is owned by the following GAMP trace chain. All behavior requirements
originate from the URS, flow through FS, and are refined by HDS → SDS → SMS before
reaching this renderer.

### Primary Chain: Renderer Policy Boundary

| Layer | ID | Description |
|-------|----|-------------|
| URS   | Model Portability; Canonical Realization and Renderer Boundary | Portable meaning, canonical-only renderer input, and no invented policy |
| FS    | FS-310 | Renderer Policy Boundary — materialize explicit canonical policy, no local allow rules |
| FS    | FS-161 / FS-162 | Canonical realization authority and peer-renderer boundary |
| FS    | FS-168 / FS-169 | Renderer consumption and rendered-output coverage |
| FS    | FS-320 | Renderer Layout Preservation — compact layouts must preserve roles/policy/hygiene |
| FS    | FS-982 | Host Configuration Renderer Boundary — NixOS host config stays thin; generated network realization belongs in renderers, not host profiles |
| HDS   | FS-310-HDS-010 | Renderer Policy Boundary hardware design — substrate facts for renderer contracts |
| SDS   | FS-310-HDS-010-SDS-010 | Renderer Policy Boundary software design — interface architecture, S88 layout, primitive registry |
| SMS   | FS-310-HDS-010-SDS-010-SMS-010 | **Coordinator** — renderer policy boundary module (SMT: OK) |
| SMS   | FS-310-HDS-010-SDS-010-SMS-040 | Interface name source binding — no hardcoded `eth0`/`ens3` |
| SMS   | FS-310-HDS-010-SDS-010-SMS-050 | nftables primitive source binding — table/chain names from canonical authority |
| SMS   | FS-310-HDS-010-SDS-010-SMS-100 | Canonical-only consumption — no raw intent, inventory, forwarding-model, or CPM parsing |
| SMS   | FS-310-HDS-010-SDS-010-SMS-110 | Fail-closed contract — missing/partial canonical input must fail |
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

### Public Ingress Runtime Destination

`FS-230-HDS-010-SDS-010-SMS-040` owns protected IPv6 public-ingress
materialization. The renderer consumes one complete canonical tuple, keeps the public
prefix value outside evaluation and the Nix store, derives the exact `/128` only
at runtime from the protected prefix plus inventory-owned endpoint IID, and
replaces one fail-closed nftables placeholder without changing rule order.
Missing, invalid, or ambiguous runtime material fails closed. IPv4 NAPT and IPv6
no-translation remain separate canonical authorities with upstream provenance.

### SMT Status (2026-06-12)

- FS-310-HDS-010-SDS-010-SMS-010: **OK** — Coordinator: NixOS tests pass (policy-endpoint, container-routing, firewall-parity, explicit-forwarding)
- FS-320-HDS-010-SDS-010-SMS-010: **OK** — Coordinator: bridge-link realization contracts pass
- All child SMS rows trace to coordinator or are in controlled SMT backlog.

### Pipeline

```
network-labs → compiler → NFM → CPM → realization → schema validation → network-renderer-nixos
```

The canonical renderer API accepts only the validated bundle boundary. Raw CPM
remains available solely to superseded direct-entry regression fixtures and is
not current controlled evidence. Production rendering must not parse
`intent.nix`, `inventory.nix`, or `inventory-nixos.nix`.

### Owning Repository

Construction tests: `network-renderer-nixos/tests/`

## Contract

- Upstream network semantics reach this renderer only through the validated
  canonical bundle.
- The optional normalized platform-binding bundle may supply NixOS mechanics,
  but may not create network meaning.
- Runtime renderer behavior must be derived from canonical input only, not from
  `intent.nix`, `inventory.nix`, `inventory-nixos.nix`, or repository-local
  source parsing.
- Missing, partial, or inconsistent input must fail evaluation.
- Renderer output must be deterministic for the same bundle and binding identities.
- Rendered debug/artifact files must expose the consumed inputs and emitted
  host/container shape for audit.

## Allowed

- Map canonical interfaces, addresses, routes, rules, services, and host/container
  selections into NixOS module fragments.
- Emit systemd-networkd, nftables, resolver, DHCP/RA, service, and validation
  configuration from explicit canonical fields.
- Consume explicit provider-neutral overlay interface semantics from the same
  validated canonical bundle.
- Map explicit logical interface identities to deterministic platform-valid
  runtime interface names where Linux-bound artifacts impose stricter limits,
  while preserving aliases for audit back to canonical and upstream identities.

## Not Allowed

- Invent topology, forwarding, policy, tenant, uplink, overlay, or DNS meaning.
- Guess behavior from node names, interface names, role names, or string tokens.
- Treat a provider name such as `nebula`, `wireguard`, or `openvpn` as generic
  forwarding truth.
- Repair missing canonical fields with local defaults.
- Consume raw CPM or another renderer's output as network-semantic authority.
- Reinterpret inventory, intent files, or examples as hidden forwarding
  authority.
- Move provider-specific runtime materialization into this renderer.

## Test Boundary

Renderer tests may load `intent.nix` and inventory files to build the upstream
pipeline through canonical realization and assert that renderer output
preserves the expected contract. A focused renderer test may also start from a
schema-validated fixture bundle. Both are test scaffolding only; the latter
proves renderer functionality, not controlled end-to-end evidence.

Production renderer code must not parse those files for meaning. If a renderer
needs a concept such as lane identity, overlay transport semantics, WAN
eligibility, delegated-prefix sources, DNS policy, or firewall behavior, that
concept must be explicit in the canonical bundle with upstream provenance.
Missing canonical data is an upstream contract bug, not a renderer inference
opportunity.

## Provider Boundary

Provider-specific runtime rendering belongs in the selected peer renderer.

Examples:

- Nebula profiles, lighthouses, unsafe routes, cert material, and daemon config
  belong in `network-renderer-nebula`.
- WireGuard peer/key/interface runtime would belong in a WireGuard renderer.
- OpenVPN runtime would belong in an OpenVPN renderer.

Peer-renderer output is not network-semantic input to this renderer. A
deployment may compose independently rendered artifacts only after each peer
has consumed the same canonical bundle identity; that composition does not
grant either renderer new network authority. This renderer must not hardcode
provider names to derive routing, firewall, WAN eligibility, or overlay
behavior.

## API

The flake exports NixOS-oriented helpers under `lib` and `libBySystem`.

Main consumers use:

- `lib.containers.buildForBox`
- `lib.hosts.buildHostFromPaths`
- `lib.renderer.canonical.hostModule { bundle; platformBinding; hostName; ... }`
  for the controlled canonical boundary
- `lib.renderer.canonical.buildHost` for focused construction
- `lib.renderer.canonical.validateInput` for boundary diagnostics
- `lib.renderer.hostModule` only for retained, superseded direct-CPM regression
  fixtures during migration

The canonical host module returns a NixOS module
  attrset carrying rendered networkd, container, module-argument and debug
  artifact output

## Tests

Run the repo-local tests before claiming conformance:

```bash
bash tests/test.sh
```

Use focused tests for touched behavior where available.
