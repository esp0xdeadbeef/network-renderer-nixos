#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

search_root="$(flake_input_path network-labs)/examples"

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
          hostEvaluated =
            (flake.inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                (builtins.toPath (repoRoot + "/s88/EquipmentModule/host/default.nix"))
                {
                  networking.hostName = "lab-host";
                }
              ];
              specialArgs = {
                controlPlaneOut = hostBuild.controlPlaneOut;
                globalInventory = hostBuild.globalInventory;
                hostContext = hostBuild.hostContext;
                renderedHostNetwork = hostBuild.renderedHost;
              };
            }).config;
          validationLoop =
            let
              unit =
                hostEvaluated.systemd.services.s88-network-validation.script;
            in
            builtins.readFile unit;
          builtContainers = flake.lib.containers.buildForBox {
            boxName = "lab-host";
            inherit system intentPath inventoryPath;
          };
          cpm = hostBuild.controlPlaneOut.control_plane_model;
          overlayA = cpm.data.enterpriseA."site-a".overlays."east-west";
          overlayB = cpm.data.enterpriseB."site-b".overlays."east-west";
          policyA = cpm.data.enterpriseA."site-a".runtimeTargets."enterpriseA-site-a-s-router-policy";
          policyB = cpm.data.enterpriseB."site-b".runtimeTargets."enterpriseB-site-b-b-router-policy";
          containerA = builtContainers."s-router-core-nebula";
          containerB = builtContainers."b-router-core-nebula";
          downstreamSelector = builtContainers."s-router-downstream-selector";
          policyOnly = builtContainers."s-router-policy-only";
          evalContainer = container:
            (flake.inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [ container.config ];
            }).config;
          nftRules = container: (evalContainer container).networking.nftables.ruleset;
          accessAdminRules = nftRules rendered.containers."s-router-access-admin";
          accessMgmtRules = nftRules rendered.containers."s-router-access-mgmt";
          accessAdminConfig = evalContainer rendered.containers."s-router-access-admin";
          accessMgmtConfig = evalContainer rendered.containers."s-router-access-mgmt";
          siteCoreWanAConfig = evalContainer rendered.containers."s-router-core-isp-a";
          siteCoreConfig = evalContainer containerA;
          branchCoreConfig = evalContainer containerB;
          downstreamConfig = evalContainer downstreamSelector;
          policyConfig = evalContainer policyOnly;
          upstreamSelectorRender =
            (evalContainer rendered.containers."s-router-upstream-selector").systemd.network;
          downstreamIngress =
            downstreamConfig.systemd.network.networks."10-access-mgmt";
          siteCoreOverlay =
            siteCoreConfig.systemd.network.networks."10-overlay-west";
          siteCoreUpstream =
            siteCoreConfig.systemd.network.networks."10-upstream";
          branchCoreOverlay =
            branchCoreConfig.systemd.network.networks."10-overlay-west";
          branchCoreUpstream =
            branchCoreConfig.systemd.network.networks."10-upstream";
          policyMgmtUplink =
            policyConfig.systemd.network.networks."10-up-mgmt-a";
          policyRules = policyConfig.networking.nftables.ruleset;
          ingressTableFor =
            network:
            let
              rule =
                lib.findFirst
                  (candidate: (candidate.SuppressPrefixLength or null) == null && (candidate.Table or null) != null)
                  null
                  (network.routingPolicyRules or [ ]);
            in
            if rule == null then null else rule.Table;
          hasNebulaForward =
            rules:
            lib.hasInfix "tcp dport 4242 dnat to 10.20.30.10" rules
            && lib.hasInfix "udp dport 4242 dnat to 10.20.30.10" rules;
          hasIngressPolicyRouting =
            builtins.isList (downstreamIngress.routingPolicyRules or [ ])
            && builtins.any
              (rule:
                (rule.IncomingInterface or null) == "access-mgmt"
                && (rule.Table or null) == 254
                && (rule.SuppressPrefixLength or null) == 0)
              (downstreamIngress.routingPolicyRules or [ ])
            && builtins.any
              (rule:
                (rule.IncomingInterface or null) == "access-mgmt"
                && (rule.Table or null) == 2004)
              (downstreamIngress.routingPolicyRules or [ ]);
          hasIngressTableRoutes =
            builtins.isList (downstreamIngress.routes or [ ])
            && builtins.any
              (route:
                (route.Table or null) == 2004
                && (route.Gateway or null) == "10.10.0.23")
              (downstreamIngress.routes or [ ]);
          hasServiceDnsPolicy =
            lib.hasInfix "comment \\\"allow-sitea-tenants-to-mgmt-dns\\\"" policyRules
            && lib.hasInfix "oifname \\\"downstream-mgmt\\\"" policyRules;
          hasDirectDnsDropOrdering =
            builtins.match
              "(.|\\n)*deny-direct-dns-egress(.|\\n)*iifname \\\"tenant-admin\\\" oifname \\\"transit\\\" accept(.|\\n)*"
              accessAdminRules
            != null
            && builtins.match
              "(.|\\n)*deny-direct-dns-egress(.|\\n)*iifname \\\"tenant-mgmt\\\" oifname \\\"transit\\\" accept(.|\\n)*"
              accessMgmtRules
            != null;
          hasCoreOverlayInputAccept =
            let
              coreRules = nftRules rendered.containers."s-router-core-nebula";
              branchCoreRules = nftRules rendered.containers."b-router-core-nebula";
            in
            lib.hasInfix "iifname \"overlay-west\" accept comment \"allow-overlay-to-core\"" coreRules
            && lib.hasInfix "iifname \"overlay-west\" accept comment \"allow-overlay-to-core\"" branchCoreRules;
          hasStrictNebulaCoreForwarding =
            let
              assertStrict =
                rules:
                lib.hasInfix "iifname \"upstream\" oifname \"overlay-west\" accept comment \"core-nebula-egress\"" rules
                && lib.hasInfix "iifname \"overlay-west\" oifname \"upstream\" accept comment \"core-nebula-return\"" rules
                && !lib.hasInfix "iifname \"upstream\" oifname { \"east-west\", \"overlay-west\" } accept" rules
                && !lib.hasInfix "iifname { \"east-west\", \"overlay-west\" } oifname \"upstream\" accept" rules
                && !lib.hasInfix "iifname \"upstream\" oifname { \"eth0\", \"overlay-west\" } accept" rules
                && !lib.hasInfix "iifname { \"eth0\", \"overlay-west\" } oifname \"upstream\" accept" rules;
            in
            assertStrict (nftRules rendered.containers."s-router-core-nebula")
            && assertStrict (nftRules rendered.containers."b-router-core-nebula");
          hasCoreIngressOverlayRoutes =
            let
              siteCoreOverlayTable = ingressTableFor siteCoreOverlay;
              siteCoreUpstreamTable = ingressTableFor siteCoreUpstream;
              branchCoreOverlayTable = ingressTableFor branchCoreOverlay;
              branchCoreUpstreamTable = ingressTableFor branchCoreUpstream;
              hasRoute =
                network: destination: gateway: table:
                builtins.any
                  (route:
                    (route.Table or null) == table
                    && (route.Destination or null) == destination
                    && (route.Gateway or null) == gateway)
                  (network.routes or [ ]);
            in
            hasRoute siteCoreOverlay "10.20.10.0/24" "10.10.0.13" siteCoreOverlayTable
            && hasRoute siteCoreOverlay "fd42:dead:beef:10::/64" "fd42:dead:beef:1000::d" siteCoreOverlayTable
            && hasRoute siteCoreUpstream "10.60.10.0/24" "100.96.10.2" siteCoreUpstreamTable
            && hasRoute siteCoreUpstream "fd42:dead:feed:10::/64" "fd42:dead:beef:ee::2" siteCoreUpstreamTable
            && hasRoute branchCoreOverlay "10.20.10.0/24" "100.96.10.1" branchCoreOverlayTable
            && hasRoute branchCoreOverlay "fd42:dead:beef:10::/64" "fd42:dead:beef:ee::1" branchCoreOverlayTable
            && hasRoute branchCoreUpstream "10.20.10.0/24" "100.96.10.1" branchCoreUpstreamTable
            && hasRoute branchCoreUpstream "fd42:dead:beef:10::/64" "fd42:dead:beef:ee::1" branchCoreUpstreamTable;
          hasBranchDnsWanScoping =
            let
              branchPolicyRules = nftRules rendered.containers."b-router-policy";
            in
            lib.hasInfix "iifname \"downstr-branch\" oifname \"upstream-branch\" udp dport 53 drop comment \"deny-branch-dns-to-wan\"" branchPolicyRules
            && lib.hasInfix "iifname \"downstr-branch\" oifname \"upstream-branch\" tcp dport 53 drop comment \"deny-branch-dns-to-wan\"" branchPolicyRules
            && !lib.hasInfix "iifname \"downstr-branch\" oifname \"up-branch-ew\" udp dport 53 drop comment \"deny-branch-dns-to-wan\"" branchPolicyRules
            && !lib.hasInfix "iifname \"downstr-branch\" oifname \"up-branch-ew\" tcp dport 53 drop comment \"deny-branch-dns-to-wan\"" branchPolicyRules
            && lib.hasInfix "iifname \"downstr-branch\" oifname \"up-branch-ew\" accept comment \"allow-branch-to-east-west\"" branchPolicyRules
            && !lib.hasInfix "iifname \"downstr-branch\" oifname \"up-hostile\" accept comment \"allow-branch-to-wan\"" branchPolicyRules
            && !lib.hasInfix "iifname \"downstr-branch\" oifname \"up-hostile-ew\" accept comment \"allow-branch-to-wan\"" branchPolicyRules
            && !lib.hasInfix "iifname \"downstr-hostile\" oifname \"upstream-branch\" accept comment \"allow-hostile-to-wan\"" branchPolicyRules
            && !lib.hasInfix "iifname \"downstr-hostile\" oifname \"up-branch-ew\" accept comment \"allow-hostile-to-wan\"" branchPolicyRules;
          hasPolicyMgmtIngressRoutes =
            builtins.isList (policyMgmtUplink.routes or [ ])
            && builtins.any
              (route:
                (route.Table or null) == 2004
                && (route.Gateway or null) == "10.10.0.45")
              (policyMgmtUplink.routes or [ ]);
          hasPolicyMgmtBranchReturnRoutes =
            let
              coreBRoutes = upstreamSelectorRender.networks."10-core-b".routes or [ ];
            in
            builtins.any
              (route:
                (route.Table or null) == 2012
                && (route.Destination or null) == "10.50.0.0/32"
                && (route.Gateway or null) == "10.10.0.12")
              coreBRoutes
            && builtins.any
              (route:
                (route.Table or null) == 2012
                && (route.Destination or null) == "fd42:dead:feed:1000:0000:0000:0000:0000/128"
                && (route.Gateway or null) == "fd42:dead:beef:1000::c")
              coreBRoutes;
          hasDerivedDnsOutgoingInterfaces =
            let
              adminOutgoing =
                accessAdminConfig.services.unbound.settings.server."outgoing-interface" or [ ];
              mgmtOutgoing =
                accessMgmtConfig.services.unbound.settings.server."outgoing-interface" or [ ];
            in
            adminOutgoing != [ ]
            && mgmtOutgoing != [ ]
            && !(builtins.elem "10.20.15.1" adminOutgoing)
            && !(builtins.elem "fd42:dead:beef:15::1" adminOutgoing)
            && !(builtins.elem "10.20.10.1" mgmtOutgoing)
            && !(builtins.elem "fd42:dead:beef:10::1" mgmtOutgoing);
          hasDeclarativeIpv6AcceptRA =
            let
              sysctls = siteCoreWanAConfig.boot.kernel.sysctl or { };
              services = siteCoreWanAConfig.systemd.services or { };
            in
            (sysctls."net.ipv6.conf.all.accept_ra" or null) == 2
            && (sysctls."net.ipv6.conf.default.accept_ra" or null) == 2
            && (sysctls."net.ipv6.conf.upstream.accept_ra" or null) == 2
            && !(builtins.hasAttr "s88-ipv6-accept-ra-upstream" services);
          hasHostValidationService =
            builtins.hasAttr "s88-network-validation" hostEvaluated.systemd.services
            && builtins.hasAttr "s88-network-validation/plan.json" hostEvaluated.environment.etc
            && builtins.elem
              "s88-network-validation-status"
              (map (pkg: pkg.pname or pkg.name or "") hostEvaluated.environment.systemPackages);
          hasEscapedValidationJqVars =
            lib.hasInfix "systemState: \\$system_state" validationLoop
            && lib.hasInfix "dnsA: \\$dns4" validationLoop
            && lib.hasInfix "dnsAAAA: \\$dns6" validationLoop;
          validationRejectsDnsServfail =
            lib.hasInfix "DNS_PROBE_NAME" validationLoop
            && lib.hasInfix "status: NOERROR" validationLoop
            && lib.hasInfix "ready: $ready" validationLoop
            && lib.hasInfix ".value.dnsA == \"ok\" and .value.dnsAAAA == \"ok\"" validationLoop;
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
          && overlayA.terminateOn == [ "s-router-core-nebula" ]
          && overlayB.terminateOn == [ "b-router-core-nebula" ]
          && hasNebulaForward (nftRules rendered.containers."s-router-core-isp-a")
          && hasNebulaForward (nftRules rendered.containers."s-router-core-nebula")
          && hasIngressPolicyRouting
          && hasIngressTableRoutes
          && hasServiceDnsPolicy
          && hasDirectDnsDropOrdering
          && hasCoreOverlayInputAccept
          && hasStrictNebulaCoreForwarding
          && hasCoreIngressOverlayRoutes
          && hasBranchDnsWanScoping
          && hasPolicyMgmtIngressRoutes
          && hasPolicyMgmtBranchReturnRoutes
          && hasDerivedDnsOutgoingInterfaces
          && hasDeclarativeIpv6AcceptRA
          && hasHostValidationService
          && hasEscapedValidationJqVars
          && validationRejectsDnsServfail
          && bgpOk
      ' >/dev/null

  pass "${example_name}"
}

run_one "dual-wan-branch-overlay"
run_one "dual-wan-branch-overlay-bgp"
