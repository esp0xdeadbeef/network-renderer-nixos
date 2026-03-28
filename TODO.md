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

---

## Test inputs for this pass

The existing `./render-all.sh` already reflects the current example layout and remains the integration entrypoint for this pass.

### Still to prove with that harness

* [ ] The renderer must succeed for the current example set:

  * [ ] `examples/multi-enterprise`
  * [ ] `examples/multi-wan`
  * [ ] `examples/overlay-east-west`
  * [ ] `examples/priority-stability`
  * [ ] `examples/single-wan`
  * [ ] `examples/single-wan-any-to-any-fw`
  * [ ] `examples/single-wan-with-nebula`
  * [ ] `examples/single-wan-with-nebula-any-to-any-fw`

---

## What is done in this pass

### Shared entry path

* [ ] Input loading and validation failures must identify the exact missing path
* [ ] The shared entry must expose one clear rendered result and optional debug output

### Equipment / host rendering

* [ ] Policy-only host rendering should stay the reference implementation and be hardened further

### Control / container selection

* [ ] Policy-only container matching should stop relying on indirect attach maps and consume canonical runtime interface data directly

---

## Renderer output contract

### Output shape

* [ ] Default renderer output should be the rendered contract, not a full dump of duplicated inputs
* [ ] `inputs` and similar trace data should move behind an explicit debug flag
* [ ] The main output should focus on rendered host and node artifacts
* [ ] Debug output may include intermediate views, but must not be the default contract

### Required top-level structure

* [ ] Rendered output should converge on a structure shaped like:

  * [ ] `render.hosts`
  * [ ] `render.nodes`
  * [ ] `metadata.sourcePaths`
  * [ ] optional `debug.*`
* [ ] Repeated copies of `intent`, `inventory`, `realization`, and per-enterprise summaries should not all exist at top level by default

### Determinism

* [ ] Re-running the renderer on the same inputs must produce byte-stable ordering
* [ ] Host, site, enterprise, unit, and interface ordering must be deterministic
* [ ] Route emission ordering must be deterministic for both IPv4 and IPv6

---

## Immediate correctness work

### Multi-enterprise / multi-site isolation

* [ ] Host-side attach target names must be namespaced so two sites on one deployment host cannot collapse onto the same bridge
* [ ] Link names alone must not be used as globally unique host-side bridge identifiers
* [ ] Enterprise + site + link identity must be preserved through rendering
* [ ] Multi-enterprise examples must prove that host equipment is isolated unless the model explicitly shares it

### Host interface naming

* [ ] Do not emit raw long link names directly as Linux interface names when they exceed kernel limits
* [ ] Introduce a deterministic shortening scheme for rendered host interface and bridge names
* [ ] Preserve the original model identity separately from the rendered interface name
* [ ] Fail clearly if a rendered interface name would collide after shortening

### Core

* [ ] Fix default route handling in the WAN container
* [ ] Ensure only intended static routes are emitted to the core-facing link
* [ ] Validate PPPoE and plain DHCP WAN modes against the same container template
* [ ] Make route emission deterministic for IPv4 and IPv6

### Access

* [ ] Stop deriving tenant VLAN purely from the third IPv4 octet
* [ ] Accept explicit VLAN ids from the control-plane model when available
* [ ] Move tenant bridge generation into a shared renderer helper
* [ ] Fail early when a tenant attachment exists without a tenant domain

### Upstream-selector

* [ ] Define a canonical `fabricSpec` shape for the upstream-selector container
* [ ] Require explicit `core` and `policy` ports instead of guessing them

### Policy-only

* [ ] Remove remaining fallback behavior from the container renderer
* [ ] Require complete runtime interface data
* [ ] Keep this unit as the strictest renderer consumer

---

## Required model invariants for the next pass

### Deployment host resolution

* [ ] Every runtime unit must resolve to exactly one deployment host
* [ ] Ambiguous fallback must hard-fail

### Runtime targets

* [ ] Role selection must be explicit and deterministic

### Runtime realization

* [ ] Every runtime interface must provide `renderedIfName`
* [ ] Every runtime interface must provide addresses and routes in canonical form
* [ ] Every runtime interface must expose exactly one connectivity type
* [ ] Downstream renderers must not reconstruct topology from scratch

### Realization inventory

* [ ] Realization data must preserve enough identity to keep host-side resources unique across enterprise/site boundaries

### Contract strictness

* [ ] Reserved traffic types such as `any` must be explicit and consistently handled
* [ ] Service/provider data must either resolve canonically or fail
* [ ] Renderer consumers must not guess missing providers, routes, interfaces, or connectivity modes
* [ ] Missing canonical runtime data must fail before rendering begins

---

## Refactor plan

### Step 3

* [ ] Extract deterministic host-side naming into one shared library module
* [ ] Include collision checks for shortened rendered interface and bridge names

### Step 4

* [ ] Extract access-specific tenant VLAN overlay rendering into a reusable equipment renderer

### Step 5

* [ ] Introduce strict, typed control-module inputs for:

  * [ ] core
  * [ ] upstream-selector
  * [ ] policy
  * [ ] access

### Step 6

* [ ] Consume one canonical runtime shape only

### Step 7

* [ ] Split renderer output into:

  * [ ] rendered contract
  * [ ] optional debug dump
  * [ ] metadata

---

## Acceptance criteria for the next iteration

### Core

* [ ] Evaluates from `intent.nix` + `inventory.nix`
* [ ] Renders host bridges and transit links
* [ ] Starts the correct WAN container
* [ ] Emits only correct WAN and fabric routes

### Upstream-selector

* [ ] Evaluates from `intent.nix` + `inventory.nix`
* [ ] Renders host transit equipment without special-case guessing
* [ ] Starts the correct upstream-selector container
* [ ] Wires explicit policy/core ports

### Policy-only

* [ ] Evaluates from `intent.nix` + `inventory.nix`
* [ ] Renders host equipment deterministically
* [ ] Renders container networking directly from canonical runtime interfaces
* [ ] Applies nftables from contract data without fallback inference

### Access

* [ ] Evaluates from `intent.nix` + `inventory.nix`
* [ ] Renders uplinks + transit + tenant VLAN bridges
* [ ] Starts the correct access containers for the local host
* [ ] Resolves tenant domains and network parameters deterministically

### Renderer output

* [ ] Default output contains rendered artifacts, not a giant duplicated input dump
* [ ] Debug output can be enabled explicitly for troubleshooting
* [ ] Multi-enterprise examples do not collapse onto shared host bridge names unless explicitly intended
* [ ] Rendered host interface names are valid and collision-free on Linux

### Integration examples

* [ ] `multi-enterprise` evaluates without cross-site bridge collisions
* [ ] `multi-wan` evaluates without role-selection ambiguity
* [ ] `overlay-east-west` evaluates without recursive shape probing
* [ ] `priority-stability` preserves deterministic ordering
* [ ] `single-wan*` examples validate common WAN container handling

---

## Definition of done for the full cleanup

* [ ] All four router roles use the same renderer pipeline shape
* [ ] All equipment modules are inventory-driven
* [ ] All control modules are runtime-target driven
* [ ] No renderer assumes one site unless the input explicitly says so
* [ ] No renderer reconstructs missing topology silently
* [ ] All failures explain exactly which input path is incomplete
* [ ] Default renderer output is small, concrete, and directly consumable
* [ ] Debug data is available when needed, but separated from the rendered contract
* [ ] Multi-enterprise rendering is isolated and deterministic on shared deployment hosts
* [ ] Rendered host/interface naming is valid, deterministic, and collision-safe

