# TODO — Initial Renderer Integration Pass

## Goal

Make the router units work in the same general flow:

1. load `intent.nix`
2. load `inventory.nix`
3. derive deployment host through `query-box`
4. render host equipment from inventory
5. render control/container wiring from control-plane + realization data
6. fail clearly when required data is missing

This pass is intentionally practical rather than perfect.


The test (inventories) cases are available to use here (example from the network-renderer-containerlab-linux-backend, but old):

```
example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)
find $example_repo -name intent.nix -type f | while read -r file; do
  echo "[*] Running for $file"

  if ! nix run .#generate-clab-config "$file"; then
    echo
    echo "[!] Generation failed for: $file"
    echo "[!] Dumping JSON files:"
    echo

    echo "Inputs file:"
    echo "===== $file ====="
    cat $file
    echo


    for j in ./*.json; do
      [ -e "$j" ] || continue
      echo "===== $j ====="
      cat "$j" | jq -c
      echo
    done

    exit 1
  fi
done
```
This is the new structure:
```
➜  ~ example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)
➜  ~ find $example_repo/examples/
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/multi-enterprise
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/multi-enterprise/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/multi-enterprise/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/multi-wan
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/multi-wan/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/multi-wan/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/overlay-east-west
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/overlay-east-west/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/overlay-east-west/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/priority-stability
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/priority-stability/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/priority-stability/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-any-to-any-fw
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-any-to-any-fw/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-any-to-any-fw/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-with-nebula
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-with-nebula/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-with-nebula/inventory.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-with-nebula-any-to-any-fw
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-with-nebula-any-to-any-fw/intent.nix
/nix/store/0d4kivyn5m1v7y6lk1fsjbgjmpq3226i-source/examples/single-wan-with-nebula-any-to-any-fw/inventory.nix
```

---

## What is done in this pass

### Shared entry path
- [x] Core already uses `queryBox.queryFromOutPath`
- [x] Access already uses `queryBox.queryFromOutPath`
- [x] Policy-only already uses `queryBox.queryFromOutPath`
- [x] Upstream-selector already uses `queryBox.queryFromOutPath`

### Equipment / host rendering
- [x] Core host networking now renders through the shared host renderer
- [x] Access host networking now uses the shared host renderer as the base
- [x] Access adds tenant VLAN bridge overlays on top of the shared host renderer
- [ ] Upstream-selector equipment should be moved fully onto the shared host renderer once transit inventory shape is stable
- [ ] Policy-only host rendering should stay the reference implementation and be hardened further

### Control / container selection
- [x] Core container selection no longer assumes exactly one enterprise and one site
- [x] Core resolves runtime targets by flattening all sites
- [x] Core resolves deployment host via `boxContext`
- [ ] Access container settings should be reduced to the same shared selection style
- [ ] Upstream-selector container settings should stop recursively probing arbitrary model shapes
- [ ] Policy-only container matching should eventually stop link-set guessing and consume canonical runtime interface data directly

---

## Immediate correctness work

### Core
- [ ] Fix default route handling in the WAN container
- [ ] Ensure only intended static routes are emitted to the core-facing link
- [ ] Validate PPPoE and plain DHCP WAN modes against the same container template
- [ ] Make route emission deterministic for IPv4 and IPv6

### Access
- [ ] Stop deriving tenant VLAN purely from the third IPv4 octet
- [ ] Accept explicit VLAN ids from the control-plane model when available
- [ ] Move tenant bridge generation into a shared renderer helper
- [ ] Fail early when a tenant attachment exists without a tenant domain

### Upstream-selector
- [ ] Replace recursive `forwardingOut`/`controlPlaneOut` probing with a strict runtime-target reader
- [ ] Define a canonical `fabricSpec` shape for the upstream-selector container
- [ ] Require explicit `core` and `policy` ports instead of guessing them
- [ ] Move host transit bridge selection to the same renderer path as other units

### Policy-only
- [ ] Remove remaining fallback behavior from the container renderer
- [ ] Require complete runtime interface data
- [ ] Keep this unit as the strictest renderer consumer

---

## Required model invariants for the next pass

### Deployment host resolution
- [ ] Every runtime unit must resolve to exactly one deployment host
- [ ] `render.hosts.<name>.deploymentHost` should win when present
- [ ] `realization.nodes.<name>.host` should be the fallback
- [ ] Ambiguous fallback must hard-fail

### Runtime targets
- [ ] All units must be read from the flattened set of site `runtimeTargets`
- [ ] No unit renderer should assume one enterprise or one site
- [ ] Role selection must be explicit and deterministic

### Runtime realization
- [ ] Every runtime interface must provide `renderedIfName`
- [ ] Every runtime interface must provide addresses and routes in canonical form
- [ ] Every runtime interface must expose exactly one connectivity type
- [ ] Downstream renderers must not reconstruct topology from scratch

### Realization inventory
- [ ] Every realization port must resolve to exactly one host-side attach target
- [ ] Bridge-backed and direct-link attachments must both be supported
- [ ] Missing bridge/link info must hard-fail

---

## Refactor plan

### Step 1
- [ ] Extract the common runtime-target flattening pattern used by core/access/upstream-selector/policy-only into one shared library module

### Step 2
- [ ] Extract common host-side bridge lookup for realization ports into one shared library module

### Step 3
- [ ] Extract access-specific tenant VLAN overlay rendering into a reusable equipment renderer

### Step 4
- [ ] Introduce strict, typed control-module inputs for:
  - [ ] core
  - [ ] upstream-selector
  - [ ] policy
  - [ ] access

### Step 5
- [ ] Remove recursive shape-probing of control-plane / forwarding outputs
- [ ] Consume one canonical runtime shape only

---

## Acceptance criteria for the next iteration

### Core
- [ ] Evaluates from `intent.nix` + `inventory.nix`
- [ ] Renders host bridges and transit links
- [ ] Starts the correct WAN container
- [ ] Emits only correct WAN and fabric routes

### Upstream-selector
- [ ] Evaluates from `intent.nix` + `inventory.nix`
- [ ] Renders host transit equipment without special-case guessing
- [ ] Starts the correct upstream-selector container
- [ ] Wires explicit policy/core ports

### Policy-only
- [ ] Evaluates from `intent.nix` + `inventory.nix`
- [ ] Renders host equipment deterministically
- [ ] Renders container networking directly from canonical runtime interfaces
- [ ] Applies nftables from contract data without fallback inference

### Access
- [ ] Evaluates from `intent.nix` + `inventory.nix`
- [ ] Renders uplinks + transit + tenant VLAN bridges
- [ ] Starts the correct access containers for the local host
- [ ] Resolves tenant domains and network parameters deterministically

---

## Definition of done for the full cleanup

- [ ] All four router roles use the same renderer pipeline shape
- [ ] All equipment modules are inventory-driven
- [ ] All control modules are runtime-target driven
- [ ] No renderer assumes one site unless the input explicitly says so
- [ ] No renderer reconstructs missing topology silently
- [ ] All failures explain exactly which input path is incomplete
