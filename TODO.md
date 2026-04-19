# TODO

## Goal

Restore the repository to the legacy/pre-rewrite execution model and file shape.

The implementation target is the legacy branch structure:

- `flake.nix`
- `lib/`
- `s88/`
- shell entrypoints for rendering and testing
- no `src/api/*` / `src/map/*` / `src/render/*` abstraction pyramid
- no JSON serialization boundary inside the renderer
- no function-valued container config crossing artifact boundaries

The rewrite must stop trying to invent a framework and instead return to a direct model:

1. load intent
2. load inventory
3. resolve model
4. render NixOS/container/vm outputs
5. write artifacts
6. run fixture tests

---

## Non-negotiable constraints

- Delete the current API/mapping/render layering once replacement paths exist.
- Do not preserve compatibility shims for the rewrite architecture.
- Do not keep function-valued renderer outputs in any JSON-shaped structure.
- Do not serialize NixOS module lambdas.
- Do not route VM rendering through a JSON artifact boundary.
- Do not split responsibility across files unless the split matches the legacy model.
- Keep orchestration shallow and obvious.
- Prefer direct attribute-set construction over staged transformation pipelines.
- Preserve only behavior, not rewrite structure.

---

## Required end state

### Repository shape

- Recreate a top-level layout modeled on legacy:
  - `lib/`
  - `s88/`
  - top-level render/test shell entrypoints
- Remove or retire rewrite-only orchestration once migration is complete:
  - `src/api/`
  - `src/map/`
  - `src/render/`
- Keep any retained files only if they map directly to legacy responsibilities.

### Renderer shape

- One direct VM renderer path that returns a concrete attrset.
- One direct container renderer path that returns concrete Nix expressions.
- One direct artifact writer path.
- No layered `build -> map -> render -> re-render -> json -> vm` loops.
- No “debug” attrsets that force evaluation of half-resolved intermediate structures.

### Data flow

- Intent and inventory are loaded once.
- S88/domain resolution happens once.
- Runtime target realization happens once.
- Rendering consumes resolved model data directly.
- Container configs remain Nix modules until written into final Nix output.
- JSON is used only for true data artifacts, never for Nix module functions.

---

## Immediate fixes

### 1. Kill function-to-JSON failures

- Find every path where container or VM outputs are passed through `builtins.toJSON` or any JSON-like coercion.
- Remove any function-valued fields from JSON-shaped outputs.
- Keep NixOS container `config = { pkgs, ... }: { ... };` as native Nix, not artifact data.
- Split “artifact metadata” from “Nix module/config payload” so only plain data is serialized.

### 2. Fix VM API shape drift

- Make `renderer.vm.build` resolve to a concrete attrset with callable operations, not to a lambda where a set is expected.
- Ensure `src/api/default.nix` exports `vm` as a set whose `build` member is directly invokable.
- Eliminate any accidental extra lambda layer introduced by currying or partial application.
- Add a regression fixture that evaluates `renderer.vm.build { ... }` without selecting through a function.

### 3. Remove debug-time forced evaluation traps

- Stop building giant `debug = { ... }` trees that traverse simulated bridges, rendered containers, and unresolved models during normal evaluation.
- Gate debug output behind opt-in flags, or remove it entirely until the renderer is stable.
- Ensure bridge/container uniqueness validation operates on plain resolved names only.

### 4. Fix simulated container naming at the source

- Resolve runtime target names once.
- Resolve container names once.
- Do not derive duplicate names from different phases.
- Enforce uniqueness in the final realized container target set, not in a mixed logical/runtime/intermediate structure.

---

## Migration plan

### Phase 1: Freeze behavior

- Snapshot the legacy branch file tree and identify direct equivalents for:
  - model loading
  - topology resolution
  - NixOS rendering
  - shell entrypoints
  - test execution
- Write a mapping document from current rewrite files to legacy responsibilities.
- Mark every rewrite file as one of:
  - keep and simplify
  - replace from legacy model
  - delete

### Phase 2: Reintroduce legacy-style entrypoints

- Recreate top-level render scripts modeled on:
  - `render-all.sh`
  - `render-home-network.sh`
  - `render-home-network-test.sh`
  - `render-single-wan.sh`
  - `test-split-box-render.sh`
- Each script should call one direct evaluation path.
- Scripts must not depend on nested API layers or mixed artifact formats.

### Phase 3: Collapse orchestration

- Replace `src/api/default.nix` with a thin top-level export surface only.
- Inline or remove orchestration layers whose only job is renaming fields between phases.
- Delete phase boundaries that do not represent real domain boundaries.

### Phase 4: Restore direct rendering

- Build VM/container outputs from fully resolved runtime targets.
- Keep renderer files output-focused:
  - input: resolved model
  - output: final Nix attrset/text
- Rendering files must not choose topology, placement, policy, or naming.

### Phase 5: Delete rewrite scaffolding

- Remove dead adapters.
- Remove duplicated model-normalization stages.
- Remove shadow APIs that wrap the real renderer.
- Remove synthetic debug structures.
- Remove compatibility glue once tests pass through the new direct path.

---

## File-by-file intent

### `flake.nix`

- Export the package/dev shell/test hooks using the direct legacy-style entrypoints.
- Avoid embedding orchestration logic here.
- Keep it as wiring only.

### `lib/`

- Hold small reusable helpers only.
- No domain orchestration.
- No renderer policy.
- No giant “utils” bucket.

### `s88/`

- Hold the domain model, topology intent, and realization logic.
- Keep process intent separate from final rendering.
- Do not mix output generation into these files.

### top-level shell scripts

- Invoke one obvious render/test action each.
- No business logic beyond selecting inputs and calling Nix.

### VM renderer

- Accept resolved inputs.
- Return a concrete attrset.
- Keep module lambdas native.
- Never serialize configs.

### Container renderer

- Accept resolved inputs.
- Return final Nix container definitions directly.
- Keep metadata separate from config payloads.

---

## Deletion targets

Delete rewrite architecture after equivalent direct paths are in place:

- any file whose sole purpose is reshaping attrs between phases
- any file that mixes lookup, normalization, policy, mapping, and rendering
- any file that exists only to support JSON artifact round-tripping
- any file that exists only for intermediate debug tree construction
- any file that turns a set API into a lambda API or vice versa without domain value

---

## Acceptance criteria

### Structural

- Repository shape resembles legacy/pre-rewrite, not the rewrite framework.
- Render/test entrypoints are top-level and direct.
- No broad `src/api`/`src/map`/`src/render` dependency ladder remains.

### Evaluation

- `renderer.vm.build { ... }` evaluates as a set-based API call.
- No `expected a set but found a function` failures.
- No `cannot convert a function to JSON` failures.
- No duplicate runtime target container name failures.

### Fixture coverage

All current passing fixtures remain passing:

- `minimal-forwarding-model`
- `minimal-forwarding-model-pppoe`
- `hosted-runtime-targets`

And the broken fixture passes:

- `default-egress-reachability`

### Output parity

- VM/container outputs match legacy intent for naming, topology, and render shape.
- Runtime targets remain stable and deterministic.
- Uplink, bridge, tenant, and p2p interface rendering stays intact.

---

## Concrete work checklist

- [ ] Inventory all current rewrite files by responsibility.
- [ ] Map each rewrite file to keep/replace/delete.
- [ ] Recreate legacy-style top-level render/test scripts.
- [ ] Simplify `flake.nix` to wire the direct path only.
- [x] Replace `renderer.vm` export with a set-based API surface.
- [x] Remove extra lambda layer causing `renderer.vm.build` failure.
- [ ] Separate plain artifact data from Nix module/function payloads.
- [ ] Remove JSON conversion from container/vm config paths.
- [ ] Keep NixOS container `config` values native.
- [ ] Remove debug attrsets that force full intermediate evaluation.
- [ ] Resolve runtime target/container names in one phase only.
- [ ] Rebuild bridge/container name uniqueness checks over resolved data only.
- [ ] Collapse orchestration layers that only rename attrs.
- [ ] Move durable helpers into `lib/`.
- [ ] Move domain realization into `s88/`.
- [ ] Remove rewrite-only adapters and scaffolding.
- [ ] Run `./tests/test-passing-fixtures.sh` until all fixtures pass.
- [ ] Compare final repo shape against legacy/pre-rewrite and remove remaining rewrite artifacts.

---

## Definition of done

Done means the repo behaves like the legacy branch in structure and execution model, not merely that the current rewrite has been patched enough to limp through tests.
