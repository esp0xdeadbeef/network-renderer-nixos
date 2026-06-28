#!/usr/bin/env bash
# GAMP-ID: FS-320-HDS-010-SDS-010-SMS-030
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${repo_root}/tests/lib/test-common.sh"

search_root="${repo_root}/tests/fixtures"

run_one() {
  local example_name="$1"
  local case_dir="${search_root}/${example_name}"
  local intent_path="${case_dir}/intent.nix"
  local inventory_path="${case_dir}/inventory-nixos.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"
  [[ -f "${inventory_path}" ]] || fail "missing inventory-nixos.nix: ${inventory_path}"

  nix_eval_true_or_fail "dual-wan-branch-overlay:${example_name}" env \
    REPO_ROOT="${repo_root}" \
    INTENT_PATH="${intent_path}" \
    INVENTORY_PATH="${inventory_path}" \
    EXAMPLE_NAME="${example_name}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = "path:" + builtins.getEnv "REPO_ROOT";
          repoPath = builtins.getEnv "REPO_ROOT";
          exampleName = builtins.getEnv "EXAMPLE_NAME";
          flake = builtins.getFlake repoRoot;
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          intentPath = builtins.getEnv "INTENT_PATH";
          inventoryPath = builtins.getEnv "INVENTORY_PATH";
          hostBuild = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-host-from-paths.nix") {
            selector = "lab-host";
            inherit system intentPath inventoryPath;
          };
          rendered = hostBuild.renderedHost;
          hostEvaluated =
            (flake.inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                (builtins.toPath (repoPath + "/s88/EquipmentModule/host/default.nix"))
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
            unit;
          builtContainers = import (builtins.getEnv "REPO_ROOT" + "/tests/nix/build-containers-from-paths.nix") {
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
          policyOnly = builtContainers."s-router-policy";
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
            policyConfig.systemd.network.networks."10-up-mgmt-a" or { };
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
          accessDoesNotPreemptPolicyDns =
            !lib.hasInfix "deny-direct-dns-egress" accessAdminRules
            && !lib.hasInfix "deny-direct-dns-egress" accessMgmtRules;
          noCoreOverlayInputAccept =
            let
              coreRules = nftRules rendered.containers."s-router-core-nebula";
              branchCoreRules = nftRules rendered.containers."b-router-core-nebula";
            in
            !lib.hasInfix "iifname \"overlay-west\" accept comment \"allow-overlay-to-core\"" coreRules
            && !lib.hasInfix "iifname \"overlay-west\" accept comment \"allow-overlay-to-core\"" branchCoreRules;
          noNixosOwnedOverlayInterface =
            let
              siteCoreNetworks = siteCoreConfig.systemd.network.networks;
              branchCoreNetworks = branchCoreConfig.systemd.network.networks;
              siteCoreExtraVeths = builtins.attrNames (containerA.extraVeths or { });
              branchCoreExtraVeths = builtins.attrNames (containerB.extraVeths or { });
              hasOverlayName = name: lib.hasInfix "overlay" name || lib.hasInfix "ovly" name;
              assertStrict =
                rules:
                lib.hasInfix "type filter hook input priority filter; policy drop;" rules
                && lib.hasInfix "iifname \"lo\" accept" rules
                && lib.hasInfix "type filter hook forward priority filter; policy drop;" rules
                && lib.hasInfix "type filter hook output priority filter; policy accept;" rules
                && !lib.hasInfix "iifname \"ens3\" oifname \"overlay-west\" accept comment \"core-lan-to-overlay\"" rules
                && !lib.hasInfix "iifname \"overlay-west\" oifname \"ens3\" accept comment \"core-overlay-to-lan\"" rules
                && !lib.hasInfix "oifname { \"ens3\", \"overlay-west\" }" rules
                && !lib.hasInfix "iifname { \"ens3\", \"overlay-west\" }" rules
                && !lib.hasInfix "iifname \"upstream\" oifname { \"east-west\", \"overlay-west\" } accept" rules
                && !lib.hasInfix "iifname { \"east-west\", \"overlay-west\" } oifname \"upstream\" accept" rules
                && !lib.hasInfix "iifname \"upstream\" oifname { \"eth0\", \"overlay-west\" } accept" rules
                && !lib.hasInfix "iifname { \"eth0\", \"overlay-west\" } oifname \"upstream\" accept" rules
                && !lib.hasInfix "nebula1" rules
                && !lib.hasInfix "eth0" rules
                && !lib.hasInfix "eth1" rules;
            in
            !(siteCoreNetworks ? "10-overlay-west")
            && !(branchCoreNetworks ? "10-overlay-west")
            && !(builtins.any hasOverlayName siteCoreExtraVeths)
            && !(builtins.any hasOverlayName branchCoreExtraVeths)
            &&
            assertStrict (nftRules rendered.containers."s-router-core-nebula")
            && assertStrict (nftRules rendered.containers."b-router-core-nebula");
          hasNebulaMssClamp =
            let
              assertClamp =
                rules:
                !lib.hasInfix "tcp option maxseg size set rt mtu" rules;
            in
            assertClamp (nftRules rendered.containers."s-router-core-nebula")
            && assertClamp (nftRules rendered.containers."b-router-core-nebula");
          hasNoNebulaCoreNat =
            let
              assertNoNat =
                rules:
                !lib.hasInfix "masquerade" rules
                && !lib.hasInfix "chain postrouting" rules;
            in
            assertNoNat (nftRules rendered.containers."s-router-core-nebula")
            && assertNoNat (nftRules rendered.containers."b-router-core-nebula");
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
          doesNotDeriveDnsOutgoingInterfaces =
            let
              adminOutgoing =
                accessAdminConfig.services.unbound.settings.server."outgoing-interface" or null;
              mgmtOutgoing =
                accessMgmtConfig.services.unbound.settings.server."outgoing-interface" or null;
            in
            adminOutgoing == null && mgmtOutgoing == null;
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
          validationStableIgnoresTimestamp =
            lib.hasInfix "del(.updatedAt)" validationLoop
            && lib.hasInfix "stable.count" validationLoop
            && lib.hasInfix "stable.json" validationLoop;
          validationBoundsContainerProbe =
            lib.hasInfix "timeout 45 systemd-run --quiet --wait --collect --pipe" validationLoop
            && lib.hasInfix "error: \"check-failed\"" validationLoop;
          validationRunsContainerProbesInParallel =
            lib.hasInfix "mktemp -d \"$state_dir/checks.XXXXXX\"" validationLoop
            && lib.hasInfix ") &" validationLoop
            && lib.hasInfix "wait" validationLoop
            && lib.hasInfix "cat \"$tmp_checks_dir/$container.json\"" validationLoop;
          renderedRouterContainersIncludeDebugTools =
            let
              packageNames =
                map (pkg: pkg.pname or pkg.name or "")
                  (evalContainer containerA).environment.systemPackages;
            in
            builtins.elem "ripgrep" packageNames
            && builtins.elem "tcpdump" packageNames
            && builtins.elem "conntrack-tools" packageNames
            && builtins.elem "curl" packageNames
            && builtins.elem "nmap" packageNames
            && builtins.elem "dnsutils" packageNames
            && builtins.elem "iproute2" packageNames
            && builtins.elem "iputils" packageNames;
          bgpOk =
            if builtins.match ".*-bgp" exampleName != null then
              policyA.routingMode == "bgp"
              && builtins.isAttrs (policyA.bgp or null)
              && policyB.routingMode == "bgp"
              && builtins.isAttrs (policyB.bgp or null)
            else
              true;
          checks = {
            containersExist = builtins.isAttrs containerA && builtins.isAttrs containerB;
            overlaysTerminateOnModeledCores =
              overlayA.terminateOn == [ "s-router-core-nebula" ]
              && overlayB.terminateOn == [ "b-router-core-nebula" ];
            accessDoesNotPreemptPolicyDns = accessDoesNotPreemptPolicyDns;
            noCoreOverlayInputAccept = noCoreOverlayInputAccept;
            noNixosOwnedOverlayInterface = noNixosOwnedOverlayInterface;
            nebulaMssClamp = hasNebulaMssClamp;
            noNebulaCoreNat = hasNoNebulaCoreNat;
            doesNotDeriveDnsOutgoingInterfaces = doesNotDeriveDnsOutgoingInterfaces;
            hostValidationService = hasHostValidationService;
            bgp = bgpOk;
          };
          failedChecks = lib.attrNames (lib.filterAttrs (_: value: value != true) checks);
        in
          if failedChecks == [ ] then true else builtins.trace "failed checks: ${builtins.toJSON failedChecks}" false
      '

  pass "${example_name}"
}

run_one "dual-wan-branch-overlay"
run_one "dual-wan-branch-overlay-bgp"
