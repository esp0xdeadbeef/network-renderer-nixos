# AGENTS.md: network-renderer-nixos

Instructions for AI agents working in this repository.

## CI: check the last GitHub Actions run, then fix what it reports

GitHub Actions is the source of truth for whether this repository is healthy.
The workflows live in `.github/workflows/`.

`tests-matrix.yml` runs on every push to `main`, and on demand. It is the only
workflow: one job per test, discovered from the repository's own contract, with the
flake check as the job every test job waits behind -- a commit that does not evaluate
never starts 288 test jobs, and "CI is green" cannot mean "the flake evaluates" while
the tests are still running. A test that fails is the answer for that commit.

`flake-lock-update.yml`, where present, bumps `flake.lock` nightly and pushes
only when the flake still checks.

### Before you start, and before you call a task done

```bash
gh run list --limit 5                # newest runs first
gh run view <run-id>                 # per-job pass/fail
gh run view <run-id> --log-failed    # only the failing step's output
gh run watch <run-id>                # follow a run you just pushed
```

Do not report work as complete while the newest run on `main` is red. Quote the
run id and its conclusion in your summary.

### Reproducing a failure

Run exactly what the job runs, from the repository root:

```bash
nix flake check --no-build -L --show-trace
NETWORK_REPO_DIRECT_TEST_OK=1 ./run-all-tests.sh
```

`NETWORK_REPO_DIRECT_TEST_OK=1` is what CI sets; it silences the
"direct repo tests are partial" guard, so leaving it off changes behaviour.

### Fixing rules

**The GAMP says a layout the bundle cannot express is a MODEL limitation, not a
renderer repair.** `FS-260-HDS-010-SDS-010`:
"A selector layout that expands one logical role into untraceable host-facing
interface fanout, or a renderer layout that discards role identity shall **fail as
a model or target limitation instead of being repaired by scripts**", and
"generated relation labels, comments, role adjacency, and runtime interface pairs
may trace a realization but **shall not authorize forwarding**".

In practice: do not derive a policy table, an ingress rule or a lane assignment in
this repository from relation records, `backingRef.lane`, topology, or a name that
happens to look right. If the canonical bundle does not let a route or rule be
mapped, fail closed with a named diagnostic and fix the producer
(`network-control-plane-model` / `network-realization-{model,schema}`), which is
where the occurrence and the runtime device name belong. Every renderer patch in
this area that "made the HAT work" by choosing a table has had to be reverted.

1. Fix the root cause in the layer that owns the behaviour. A red job is a
   defect in this repository — never "pre-existing", "environmental", "a
   flake", or "not mine".
2. Never make a test pass by deleting it, weakening an assertion, adding a
   skip/opt-in flag, or widening an error path with `|| true`. A test that
   passes because it stopped asserting is still a failure.
3. If the documentation a test asserts is stale, update the documentation *and*
   the test to the current contract. Do not bend the code to an obsolete spec.
4. If a tool is missing from the runner, add it to the `Install test
   dependencies` step. Do not guard the test on the tool's absence.
5. Tests that need live infrastructure (containers, live hosts, secrets) stay
   opt-in and must remain skipped in CI; they must not become silently passing
   because the environment lacks them.
