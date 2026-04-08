# network-renderer-nixos

A deterministic renderer that converts an explicit, platform-independent **control-plane model** into **NixOS-specific configuration**.

This repository is the **emission stage**.
It does not define topology.
It does not define forwarding semantics.
It does not define policy meaning.

It takes already-declared network meaning and renders that meaning into NixOS configuration.

The renderer is intentionally **strict**.

It does not repair missing control-plane data.
It does not reinterpret upstream contracts.
It does not invent deployment meaning from partial hints.

If upstream data is incomplete, inconsistent, or semantically unresolved, rendering must fail.

---

# Disclaimer

This project exists primarily to support my own infrastructure.

If it happens to be useful to others, great — but **pin a specific version**.
The internal schema and renderer shape may change between versions.
Backward compatibility is **not guaranteed**.

Pull requests are welcome, but changes that weaken the architectural boundaries are unlikely to be merged.

This repository is not trying to be a universal network templating engine.
It is a **contract-first NixOS renderer** for an already-explicit network model.

---

# Normative implementation

The Nix implementation in this repository is the only normative implementation.

Historical notes, experiments, scratch files, and old layouts are **non-normative**.
They do not define accepted input shape, renderer guarantees, or failure semantics.

In practice, the renderer behavior defined by the main Nix path is the contract.

---

# Reality check

If your environment is small enough that you can hand-write a few interfaces, routes, firewall rules, and service bindings, this repository is probably **completely unnecessary**.

You could solve many small cases with a handful of NixOS options and be done.

Something like:

```nix
{
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.0.2";
      prefixLength = 24;
    }
  ];

  networking.defaultGateway = "10.0.0.1";
}
```

Done.

This repository exists because I chose to build something much stricter and much more explicit instead.

The goal is not merely to make packets move.
The goal is to have:

* deterministic rendering
* strict architectural boundaries
* explicit upstream authority
* platform-specific emission without platform-specific reinterpretation
* failure on mismatch instead of silent repair
* reproducible NixOS output from explicit model input

For a trivial setup, that is overkill.

Once the network stops being trivial, that strictness starts to matter.

---

# Project intent

This repository sits **after** the control-plane model.

Its job is to take:

* explicit control-plane structure
* explicit realized interface and node bindings
* explicit renderer-consumable network meaning

and produce:

* explicit NixOS configuration
* explicit host and service configuration shape
* deterministic platform output

It is therefore a **renderer**, not a control-plane synthesizer and not a topology compiler.

It does not decide what the network means.
It decides how already-declared meaning is emitted into NixOS.

---

# What this project does

`network-renderer-nixos`:

* consumes explicit control-plane data
* validates that required renderer inputs exist
* maps normalized control-plane structure into NixOS configuration
* renders concrete interface, routing, and service configuration
* emits deterministic NixOS output for hosts and related runtime targets
* preserves upstream meaning instead of reconstructing it

Typical rendered output may include things like:

* interface configuration
* address assignment
* route emission
* firewall configuration
* resolver and DHCP-related settings
* host-local service bindings
* container or runtime-target configuration when explicitly selected by the consumer
* NixOS module output suitable for evaluation

The result is **NixOS-specific configuration**, not a new network model.

---

# What this project does not do

This project does **not**:

* invent forwarding intent
* invent transit topology
* invent tenant identity
* invent overlay membership
* invent policy membership
* invent BGP peers
* invent uplink semantics
* repair missing control-plane data
* infer deployment meaning from naming conventions
* reinterpret upstream policy semantics
* use inventory as a hidden source of forwarding truth
* silently choose a different architecture because the input was inconvenient

This repository is not allowed to turn partial data into made-up configuration.

If upstream says something must exist and the renderer cannot render it from the explicit inputs provided, evaluation must fail.

---

# Position in the architecture

This repository is part of a multi-stage pipeline.

| Layer                   | Responsibility                                                                |
| ----------------------- | ----------------------------------------------------------------------------- |
| **Compiler**            | defines communication semantics and canonical staged topology                 |
| **Forwarding model**    | constructs deterministic forwarding structure from the canonical staged model |
| **Control plane model** | joins explicit forwarding intent with explicit realization inputs             |
| **Renderer**            | emits platform-specific configuration                                         |

Pipeline:

```text
intent
  ↓
compiler
  ↓
forwarding model
  ↓
control plane model
  ↓
renderer-nixos
```

This repository implements the **NixOS renderer stage**.

---

# Architectural boundary

The control-plane model is the canonical source of rendered network meaning.

The renderer is not allowed to override that meaning.

That boundary matters.

The control-plane layer decides the explicit, realized structure that a renderer should consume.
The renderer decides how that structure becomes valid NixOS configuration.

Those are different responsibilities.

This repository may contain convenience entrypoints that evaluate more than one stage together.
That does **not** change the architecture.
It only changes where evaluation starts.

Even when invoked through a higher-level entrypoint, the renderer still must behave like a renderer:

* it consumes explicit upstream contracts
* it emits NixOS grammar
* it fails on unresolved inputs
* it does not become a hidden compiler or hidden control-plane solver

---

# Source of truth

The source of truth split is hard.

## Upstream model layers own meaning

Upstream owns:

* topology meaning
* forwarding semantics
* tenant and overlay identity
* policy relation identity
* uplink and exit intent
* transit structure
* explicit realization bindings already resolved at the control-plane layer

## The renderer owns emission

The renderer owns:

* mapping explicit model data into NixOS options
* preserving already-established semantics
* emitting deterministic platform configuration
* failing when required renderer inputs are missing or contradictory

No third source of truth is allowed to appear during rendering.

The renderer is not allowed to “figure it out” from:

* hostnames
* interface naming patterns
* partial inventory hints
* container names
* missing defaults
* guessed role behavior

If the emitted configuration requires a fact, that fact must already be explicit at the renderer boundary.

---

# Renderer stance

This repository is **platform-specific** and **semantically conservative**.

Platform-specific means:

* it emits NixOS configuration
* it may rely on NixOS module structure
* it may target NixOS-native facilities for networking, services, and host realization

Semantically conservative means:

* it does not invent network meaning
* it does not reinterpret upstream intent
* it does not perform policy repair
* it does not derive missing structure from platform shortcuts

That distinction is important.

This project is allowed to be NixOS-specific.
It is **not** allowed to be architecture-specific in a way that changes upstream meaning.

---

# Consumer boundary

The renderer and the consumer are not the same thing.

That boundary must stay clean.

The renderer should render explicit units and runtime targets from explicit input contracts.

The consumer layer decides things like:

* which rendered hosts or units are enabled
* which containers should exist on a given host
* whether a rendered target should autostart
* extra runtime toggles or capabilities
* deployment-time inclusion or exclusion choices

Those are **consumer decisions**, not renderer decisions.

The renderer should not embed hidden deployment policy just because it can.

A renderer that silently decides what the user probably wanted is doing the wrong job.

---

# No hidden inference

`network-renderer-nixos` does not invent platform output from incomplete semantics.

It does not infer:

* missing tenant bindings
* missing overlay bindings
* missing uplink realization
* missing firewall intent
* missing interface ownership
* missing route meaning
* missing node-role semantics
* missing container selection policy

It only renders what has already been made explicit upstream and what has explicitly been selected at the consumer boundary.

---

# Determinism

Given the same explicit renderer inputs, output must be deterministic.

That means:

* same input should produce the same rendered configuration
* missing data should fail the same way every time
* platform output should not depend on accidental evaluation order
* renderers should not smuggle in hidden defaults that change meaning silently

Strict rendering is the point.

Not a side effect.

---

# Why strict failure matters

A renderer is the worst place to hide semantic repair.

By the time data reaches the renderer, architecture decisions should already be settled.

If the renderer starts compensating for missing meaning, you get the worst of both worlds:

* upstream contracts stop being trustworthy
* platform output becomes harder to reason about
* failures turn into silent drift
* deployment behavior becomes dependent on renderer quirks

That is exactly what this repository is trying to avoid.

The renderer should be boring.

Input in.
Configuration out.
Crash on mismatch.

---

# Practical expectation for downstream use

If you use this repository, the expectation is simple:

* provide explicit upstream model data
* keep responsibility boundaries intact
* let the renderer emit NixOS-specific configuration
* do not expect the renderer to solve missing architecture for you
* do not expect it to reverse-engineer intent from partial data

You may choose how to wire the rendered output into your deployment.
You may choose how to package the emitted modules.
You may choose how to assemble host-specific consumers.

But the renderer is not allowed to change what the model means.

---

# Genericity boundary

This project is **generic across NixOS deployments**, not generic across arbitrary network philosophies.

That means:

* the same explicit upstream model can be rendered into consistent NixOS output
* different consumers may choose different deployment layouts around the same rendered results
* the renderer can remain reusable without becoming policy-ambiguous

It does **not** mean:

* missing contracts are acceptable
* platform emission may redefine semantics
* deployment convenience may override upstream authority
* host realization may retroactively define forwarding meaning

The genericity boundary is:

> one explicit upstream model, one explicit renderer contract, many possible NixOS deployment consumers.

---

# Summary

This project is a deterministic NixOS renderer.

It accepts:

* an explicit upstream control-plane result
* explicit realized renderer inputs
* explicit consumer-side selection where deployment choices are required

and produces:

* deterministic, explicit, NixOS-specific configuration

It is:

* NixOS-specific
* strict about architectural boundaries
* intolerant of guessing
* deterministic in output
* conservative about semantic ownership

Upstream defines what the network means.
The renderer defines how that meaning is emitted in NixOS.
The consumer decides what to instantiate or enable at deployment time.

If those layers do not line up, rendering should fail.

That is the design.

