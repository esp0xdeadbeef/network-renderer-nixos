# Implementation Plan

Goal: make the NixOS renderer a strict S88 consumer with explicit host/runtime requirements, while pushing any missing semantic data upstream into CPM or inventory instead of inventing it locally.

## Current S88 posture

This renderer is explicit about boundaries and strictness. That is good.

The main remaining issue is that some NixOS-specific realization needs are real, but they are not yet described as part of the shared contract strongly enough. The most obvious case is host WAN-uplink selection.

## Main gaps

1. WAN-group to host-uplink mapping is stricter than the common docs currently imply.
   - The renderer correctly fails when host uplink assignment is ambiguous.
   - But the shared examples/docs do not yet present this as a first-class requirement.

2. Renderer input expectations are broader than the README examples show.
   - Runtime targets, host/container projections, overlay provisioning hints, services, uplinks, and port realizations should be described more concretely.

3. Some convenience entrypoints still blur stage boundaries.
   - They are useful, but the README should keep reminding readers that the renderer is not solving control-plane semantics.

4. There is still some inventory-path and example-path fallback behavior.
   - That is practical, but should remain clearly convenience-only rather than a semantic data source.

## Work items

1. Add a “required consumer-side selections” section to `README.md`.
   - Explicitly document host WAN mapping requirements:
     - `render.hosts.<host>.wanUplink`
     - `render.hosts.<host>.wanGroupToUplink`
     - or equivalent deployment-side selectors

2. Push shared semantics upstream where possible.
   - If WAN group identity is common, CPM should expose it cleanly.
   - The renderer should only perform final host binding, not infer group semantics.

3. Document the renderer’s exact CPM expectations.
   - runtime targets
   - site projections
   - overlays
   - realized interfaces
   - service exposure and forwarding
   - host/container placement

4. Make example guidance stricter.
   - `network-labs` examples intended for NixOS should include explicit `inventory-nixos.nix` where host-uplink mapping differs from generic inventory.

5. Add cross-repo conformance tests.
   - Multi-uplink and multi-site overlay examples should fail fast when host WAN mapping is omitted, and pass once explicit mapping is present.

## Exit criteria

- NixOS renderer failures are predictable and documented, not surprising.
- Example inventories reflect the strict WAN mapping contract.
- The renderer remains strict without being forced to invent missing deployment meaning.
- Shared docs explain which requirements are NixOS-specific bindings versus common S88 semantics.

## Test impact

- Keep the broad passing-fixtures sweep.
- Keep explicit multi-wan and BGP cases.
- Add a test pair for:
  - missing host WAN mapping fails
  - explicit host WAN mapping passes
