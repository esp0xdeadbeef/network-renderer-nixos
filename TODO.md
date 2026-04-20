# TODO

`network-renderer-nixos` is a pure renderer: it must accept arbitrary CPM topologies and emit NixOS artifacts without
inventing semantics (static vs BGP, lane derivation, overlay membership, etc).

## Consume CPM IPv6 Outputs (PD + Tenant Modes)

Status: CPM emits deterministic IPv6 PD plans and per-tenant modes; renderer support is pending.

- Consume `control_plane_model.data.<enterprise>.<site>.ipv6`:
  - configure SLAAC/DHCPv6/static behavior per tenant as explicitly declared
  - do not allocate prefixes in the renderer; consume CPM slots/prefixes only
- Add offline tests (no VM boot) that assert the rendered NixOS/networkd/radvd artifacts match CPM output.

## Consume CPM Uplink Egress Routing Outputs

Status: CPM emits `routing.uplinks` and can append eBGP neighbors to `runtimeTargets.*.bgp.neighbors`.

- Ensure BGP/static config is emitted only when CPM declares it.
- Add offline tests that assert:
  - BGP neighbors show up in rendered FRR/system config when present
  - static uplink route lists are emitted when present

## Overlay Provisioning (Nebula / WireGuard / etc.)

Status: CPM emits overlay termination nodes + per-node overlay IPs.

- For each supported overlay provider (starting with Nebula):
  - emit a renderer artifact that makes provisioning explicit (which nodes/profiles must exist; which overlay IP to use)
  - keep provider-specific knobs in inventory and treat them as opaque payloads unless strictly required
- Add offline tests that validate overlay interface IP assignment and basic daemon config emission.

## Renderer Strictness / Validation Boundaries

- Do not duplicate compiler/forwarding-model/CPM semantic validation.
- Fail only on renderer-local invariants:
  - malformed CPM input schema for fields this renderer consumes
  - missing runtime realization fields required to emit NixOS artifacts
  - internal name collisions in the rendered artifact set

