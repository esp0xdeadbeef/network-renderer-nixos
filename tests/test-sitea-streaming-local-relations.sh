#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

example_root="${repo_root}/tests/fixtures/s-router-overlay-dns-lane-policy"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

[[ -f "${intent_path}" ]] || { echo "missing intent: ${intent_path}" >&2; exit 1; }
[[ -f "${inventory_path}" ]] || { echo "missing inventory: ${inventory_path}" >&2; exit 1; }

read -r -d '' expr <<'EOF' || true
let
  repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
  intentPath = builtins.getEnv "INTENT_PATH";
  inventoryPath = builtins.getEnv "INVENTORY_PATH";
  flake = builtins.getFlake repoRoot;
  system = builtins.currentSystem;
  hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
    selector = "s-router-test";
    inherit system intentPath inventoryPath;
  };
  rendered = hostBuild.renderedHost;
  policyCfg =
    (flake.inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ rendered.containers."s-router-policy-only".config ];
    }).config;
  rules = policyCfg.networking.nftables.ruleset;
  # The rendered rules carry an explicit `ip saddr <tenant-prefix>` match, which
  # is FS-300 source-scope validation: a relation allow is scoped to the source
  # prefix the model declares, not left as an any-source accept. Asserting the
  # accept without that match could never succeed and, worse, would pass if the
  # scope check were dropped. Match the whole rule line instead.
  #
  # `builtins.split "\n"` is used rather than `lib.hasInfix` on the full
  # ruleset: the s-router-policy ruleset is >100 KB, and the single-pass
  # string builtins overflow the evaluator stack on it ("stack overflow
  # (possible infinite recursion)") even though the content is correct.
  ruleLines = builtins.filter builtins.isString (builtins.split "\n" rules);
  hasRule = fragment: builtins.any (l: builtins.match ".*${fragment}.*" l != null) ruleLines;

  permitComment = "accept comment \"allow-sitea-client-to-streaming-chromecast\"";
in
  builtins.substring 0 0 "" == ""
  && hasRule "iifname \"down-client\" oifname \"downstr-stream\" ip saddr .*${permitComment}"
  && hasRule "iifname \"down-client2\" oifname \"downstr-stream\" ip saddr .*${permitComment}"
  && !(hasRule "iifname \"downstr-stream\" oifname \"down-client\" .*${permitComment}")
  && !(hasRule "iifname \"downstr-stream\" oifname \"down-client2\" .*${permitComment}")
EOF

result="$(
  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr "${expr}"
)"

[[ "${result}" == "true" ]]

echo "PASS sitea-streaming-local-relations"
