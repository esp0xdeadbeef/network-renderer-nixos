#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

threshold_ms="${NIXOS_RENDERER_BENCH_THRESHOLD_MS:-3000}"
if ! [[ "${threshold_ms}" =~ ^[0-9]+$ ]] || [ "${threshold_ms}" -lt 1 ]; then
  echo "FAIL fs940-semantic-eval: NIXOS_RENDERER_BENCH_THRESHOLD_MS must be a positive integer" >&2
  exit 1
fi

repo_revision="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo unknown)"
repo_dirty=false
if ! git -C "${repo_root}" diff --quiet >/dev/null 2>&1 || ! git -C "${repo_root}" diff --cached --quiet >/dev/null 2>&1; then
  repo_dirty=true
fi
locked_revisions="$(jq -r '[.nodes | to_entries[] | select(.value.locked.rev?) | "\(.key)=\(.value.locked.rev)"] | join(",")' "${repo_root}/flake.lock")"
host_class="$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"
excluded_runtime_stages="nix-build,container-image-build,vm-deployment,containerlab-deployment,boot,live-packet-validation,provider-calls,cache-misses"

archive_json="$(mktemp)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-fs940.XXXXXX")"
trap 'rm -f "${archive_json}"; rm -rf "${tmp_dir}"' EXIT
nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
nixpkgs_path="$(jq -er '.inputs["nixpkgs"].path' "${archive_json}")"
render_summary_expr="${tmp_dir}/render-summary.nix"

cat >"${render_summary_expr}" <<'NIX'
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  nixpkgsPath = builtins.getEnv "NIXPKGS_PATH";
  lib = import (builtins.toPath (nixpkgsPath + "/lib"));
  api = import (builtins.toPath (repoRoot + "/s88/Enterprise/default.nix")) {
    inherit lib;
    repoRoot = builtins.toPath repoRoot;
    flakeInputs = { };
  };
  cpm = builtins.fromJSON (builtins.readFile (builtins.getEnv "CPM_PATH"));
  rendered = api.renderer.renderDryConfig {
    cpmPath = builtins.getEnv "CPM_PATH";
    exampleDir = builtins.dirOf (builtins.getEnv "CPM_PATH");
    debug = true;
  };
  cpmSites =
    builtins.concatMap
      (enterpriseName:
        map
          (siteName: builtins.getAttr siteName (builtins.getAttr enterpriseName cpm.control_plane_model.data))
          (builtins.attrNames (builtins.getAttr enterpriseName cpm.control_plane_model.data)))
      (builtins.attrNames cpm.control_plane_model.data);
in
{
  upstream = {
    sites = builtins.length cpmSites;
    runtimeTargets = builtins.foldl'
      (acc: site: acc + builtins.length (builtins.attrNames (site.runtimeTargets or { }))) 0 cpmSites;
    interfaces = builtins.foldl'
      (acc: site: acc + builtins.foldl'
        (racc: rt: racc + builtins.length (builtins.attrNames (rt.interfaces or { }))) 0
        (builtins.attrValues (site.runtimeTargets or { }))) 0 cpmSites;
  };
  downstream = {
    hosts = builtins.length (builtins.attrNames (rendered.render.hosts or { }));
    nodes = builtins.length (builtins.attrNames (rendered.render.nodes or { }));
    containers = builtins.foldl'
      (acc: host: acc + builtins.length (builtins.attrNames host)) 0
      (builtins.attrValues (rendered.render.containers or { }));
  };
}
NIX

examples=(
  "hat-emulated-isp-residential-testnet:${labs_root}/GAMP/HAT/emulated-isp-residential-testnet/intent.nix:${labs_root}/GAMP/HAT/emulated-isp-residential-testnet/inventory-nixos.nix"
  "sat-controlled-baseline:${labs_root}/GAMP/SAT/intent.nix:${labs_root}/GAMP/SAT/inventory-nixos.nix"
)

failed=0

for example_spec in "${examples[@]}"; do
  example="${example_spec%%:*}"
  rest="${example_spec#*:}"
  intent="${rest%%:*}"
  inventory="${rest#*:}"
  cpm_json="${tmp_dir}/${example}.cpm.json"
  if [[ ! -f "${intent}" || ! -f "${inventory}" ]]; then
    echo "FAIL fs940-semantic-eval ${example}: missing intent or inventory" >&2
    failed=1
    continue
  fi

  REPO_ROOT="${repo_root}" INTENT_PATH="${intent}" INVENTORY_PATH="${inventory}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json \
      --file "${repo_root}/tests/nix/build-cpm-from-paths.nix" \
      >"${cpm_json}"

  start_ms="$(date +%s%3N)"
  if ! summary="$(
    env REPO_ROOT="${repo_root}" NIXPKGS_PATH="${nixpkgs_path}" CPM_PATH="${cpm_json}" INVENTORY_PATH="${inventory}" \
      timeout "$((threshold_ms / 1000 + 20))" \
      nix eval \
        --extra-experimental-features 'nix-command flakes' \
        --impure \
        --json \
        --file "${render_summary_expr}"
  )"; then
    end_ms="$(date +%s%3N)"
    elapsed_ms=$((end_ms - start_ms))
    echo "BENCH fs940 stage=network-renderer-nixos example=${example} status=FAIL elapsed_ms=${elapsed_ms} threshold_ms=${threshold_ms} repo_revision=${repo_revision} repo_dirty=${repo_dirty} locked_revisions=${locked_revisions} timing_method=date_ms host_class=${host_class} cache_state=warm-required command=nix-eval-direct-renderDryConfig upstream_cardinality=unknown downstream_cardinality=unknown excluded_runtime_stages=${excluded_runtime_stages}" >&2
    failed=1
    continue
  fi
  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))

  status=PASS
  if [ "${elapsed_ms}" -gt "${threshold_ms}" ]; then
    status=FAIL
    failed=1
  fi

  upstream_cardinality="$(jq -r '.upstream | to_entries | map("\(.key):\(.value)") | join(",")' <<<"${summary}")"
  downstream_cardinality="$(jq -r '.downstream | to_entries | map("\(.key):\(.value)") | join(",")' <<<"${summary}")"

  echo "BENCH fs940 stage=network-renderer-nixos example=${example} status=${status} elapsed_ms=${elapsed_ms} threshold_ms=${threshold_ms} repo_revision=${repo_revision} repo_dirty=${repo_dirty} locked_revisions=${locked_revisions} timing_method=date_ms host_class=${host_class} cache_state=warm-required command=nix-eval-direct-renderDryConfig upstream_cardinality=${upstream_cardinality} downstream_cardinality=${downstream_cardinality} excluded_runtime_stages=${excluded_runtime_stages}"
done

exit "${failed}"
