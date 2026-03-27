# TODO — Per-Repository Plan

---

## 1) nixos-network-compiler (Intent Layer)

### Scope

Defines **communication semantics only**. No topology, no routing, no runtime artifacts.

### Tasks

* [ ] Enforce strict schema for:

  * [ ] `trafficTypes`
  * [ ] `services`
  * [ ] `relations`
* [ ] Validate relations:

  * [ ] source/target kinds exist
  * [ ] priorities are deterministic
  * [ ] no ambiguous overlaps (same match, conflicting actions)
* [ ] Ensure output contains **no**:

  * [ ] interface names
  * [ ] routing constructs
  * [ ] device-level data
* [ ] Emit stable identifiers for all entities (ids, names)
* [ ] Deterministic ordering of all collections

### Tests

* [ ] Failing: invalid relation targets
* [ ] Failing: conflicting rules
* [ ] Passing: identical input → identical output (hash check)

---

## 2) Forwarding Model (Structure Layer)

### Scope

Builds deterministic **topology + forwarding structure** from compiler output.

### Tasks

* [ ] Construct nodes and roles:

  * [ ] access, policy, upstream-selector, core
* [ ] Build links:

  * [ ] deterministic link naming
  * [ ] stable ordering
* [ ] Validate topology:

  * [ ] no disconnected nodes
  * [ ] required roles present
* [ ] Define attachment points:

  * [ ] tenant attachments
  * [ ] service endpoints
* [ ] Emit canonical structure:

  * [ ] nodes
  * [ ] links
  * [ ] attachments

### Invariants

* [ ] Every link has exactly two endpoints
* [ ] No implicit links
* [ ] No ordering-dependent behavior

### Tests

* [ ] Failing: missing required role
* [ ] Failing: orphan node
* [ ] Passing: stable topology ordering

---

## 3) Control Plane Model (Realization Layer) ⚠️ CURRENT BUG AREA

### Scope

Derives **fully explicit runtime realization**. Must be render-complete.

### Critical Tasks

#### 3.1 Emit canonical runtime interfaces

* [ ] Provide `effectiveRuntimeRealization.interfaces`

Each interface MUST include:

* [ ] `runtimeIfName`

* [ ] `renderedIfName`

* [ ] exactly one of:

  * [ ] `link`
  * [ ] `attachment`

* [ ] `addr4` (list)

* [ ] `addr6` (list)

* [ ] `routes` (list)

* [ ] HARD FAIL if any field missing

#### 3.2 Remove port abstraction completely

* [ ] Delete:

  * [ ] `runtimePorts`
  * [ ] `portMatches`
  * [ ] any port→interface logic

* [ ] Ensure link binding is fully resolved into interfaces

#### 3.3 Deterministic naming

* [ ] `renderedIfName` MUST be:

  * [ ] unique per node
  * [ ] stable
  * [ ] not order-derived

#### 3.4 Route canonicalization

* [ ] Emit routes as list:

```
{ dst, via4?, via6? }
```

* [ ] No normalization required downstream

#### 3.5 Connectivity correctness

* [ ] Every interface has exactly one connectivity type
* [ ] All links exist and are matched
* [ ] No orphan interfaces

### Tests

* [ ] Missing `renderedIfName` → FAIL
* [ ] Duplicate interface names → FAIL
* [ ] Interface without link/attachment → FAIL
* [ ] Both link + attachment → FAIL

---

## 4) Renderer (Projection Layer)

### Scope

Pure projection into platform config (NixOS, containerlab, etc.)

### Rules

* [ ] NO inference
* [ ] NO fallback
* [ ] NO topology reconstruction

### Tasks

* [ ] Read only:

  * [ ] `renderedIfName`
  * [ ] addresses
  * [ ] routes
  * [ ] link/attachment

* [ ] Emit configuration directly

* [ ] Fail if input incomplete

### Forbidden

* [ ] fallback to `runtimeIfName`
* [ ] link-based matching
* [ ] port-based mapping
* [ ] skipping data silently

### Tests

* [ ] Incomplete model → renderer fails
* [ ] No fallback paths exist

---

## 5) Cross-Stage Invariants

* [ ] No stage introduces ambiguity
* [ ] Each stage strictly reduces ambiguity
* [ ] No duplicated abstractions (ports vs interfaces)
* [ ] Deterministic output at every stage

---

## Immediate Execution Plan

1. Fix control-plane model (render-complete interfaces)
2. Add hard failures for missing fields
3. Remove renderer fallbacks
4. Introduce temporary adapter (optional, upstream only)
5. Delete port abstraction
6. Expand invariant tests

---

## End State

* Compiler = pure intent
* Forwarding model = deterministic structure
* Control plane = fully explicit realization
* Renderer = trivial projection

No guessing anywhere in the pipeline.

