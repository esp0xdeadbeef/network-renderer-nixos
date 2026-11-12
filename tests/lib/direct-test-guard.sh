#!/usr/bin/env bash
# GAMP-SCOPE: runner-only; not SMT acceptance evidence
#
# Shared guard for the direct-repository SMS cases under `tests/lib/`.
#
# Those cases assert the contract of *this* repository in isolation: they grep
# `lib/` for a diagnostic, evaluate a single `compilePath`, or compare two runs
# of the flake app. That is a partial view. The locked, full sweep additionally
# rebuilds the sibling network-* layers and runs live validation, and is the only
# run that can call a contract fully exercised.
#
# Sourcing this file must never change the case's verdict. It only records that
# the run was partial, so a green direct run is never mistaken for the locked
# sweep. Callers that require the full sweep opt in with
# `NETWORK_REPO_SWEEP=1`; callers that intentionally run the focused cases set
# `NETWORK_REPO_DIRECT_TEST_OK=1` and are told nothing.
#
# This mirrors the guard in tests/check.sh so both entry paths agree.

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run network-codex-agent/scripts/s-router-full-lab-rebuild-loop.sh for the locked full network-* sweep plus live validation." >&2
fi
