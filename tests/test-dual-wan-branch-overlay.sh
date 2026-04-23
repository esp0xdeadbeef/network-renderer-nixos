#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
search_root="${repo_root}/../network-labs/examples"

source "${repo_root}/tests/lib/test-common.sh"

run_one() {
  local example_name="$1"
  local case_dir="${search_root}/${example_name}"
  local intent_path="${case_dir}/intent.nix"
  local inventory_path="${case_dir}/inventory-nixos.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
  [[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

  REPO_ROOT="${repo_root}" \
  INTENT_PATH="${intent_path}" \
  INVENTORY_PATH="${inventory_path}" \
  EXAMPLE_NAME="${example_name}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          exampleName = builtins.getEnv "EXAMPLE_NAME";
          flake = builtins.getFlake repoRoot;
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          hostBuild = flake.lib.renderer.buildHostFromPaths {
            selector = "lab-host";
            inherit system intentPath inventoryPath;
          };
          rendered = hostBuild.renderedHost;
          cpm = hostBuild.controlPlaneOut.control_plane_model;
          overlayA = cpm.data.enterpriseA."site-a".overlays."east-west";
          overlayB = cpm.data.enterpriseB."site-b".overlays."east-west";
          policyA = cpm.data.enterpriseA."site-a".runtimeTargets."enterpriseA-site-a-s-router-policy";
          policyB = cpm.data.enterpriseB."site-b".runtimeTargets."enterpriseB-site-b-b-router-policy";
          containerA = rendered.containers."s-router-core-isp-b";
          containerB = rendered.containers."b-router-core";
          downstreamSelector = rendered.containers."s-router-downstream-selector";
          evalContainer = container:
            (flake.inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ container.config ];
            }).config;
          nftRules = container: (evalContainer container).networking.nftables.ruleset;
          coreRulesA = evalContainer rendered.containers."s-router-core-isp-a";
          coreRulesB = evalContainer rendered.containers."s-router-core-isp-b";
          downstreamConfig = evalContainer downstreamSelector;
          downstreamTransit =
            downstreamConfig.systemd.network.networks."10-policy-mgmt"
              or downstreamConfig.systemd.network.networks."10-policy-admin";
          hasNebulaForward =
            rules:
            lib.hasInfix "tcp dport 4242 dnat to 10.20.30.10" rules
            && lib.hasInfix "udp dport 4242 dnat to 10.20.30.10" rules;
          hasIngressPolicyRouting =
            builtins.isList (downstreamTransit.routingPolicyRules or [ ])
            && builtins.any
              (rule:
                (rule.IncomingInterface or null) == "policy-mgmt"
                && builtins.isInt (rule.Table or null))
              (downstreamTransit.routingPolicyRules or [ ]);
          bgpOk =
            if builtins.match ".*-bgp" exampleName != null then
              policyA.routingMode == "bgp"
              && builtins.isAttrs (policyA.bgp or null)
              && policyB.routingMode == "bgp"
              && builtins.isAttrs (policyB.bgp or null)
            else
              true;
        in
          builtins.isAttrs containerA
          && builtins.isAttrs containerB
          && overlayA.terminateOn == [ "s-router-core-isp-b" ]
          && overlayB.terminateOn == [ "b-router-core" ]
          && hasNebulaForward (nftRules rendered.containers."s-router-core-isp-a")
          && hasNebulaForward (nftRules rendered.containers."s-router-core-isp-b")
          && hasIngressPolicyRouting
          && bgpOk
      ' >/dev/null

  pass "${example_name}"
}

run_one "dual-wan-branch-overlay"
run_one "dual-wan-branch-overlay-bgp"
