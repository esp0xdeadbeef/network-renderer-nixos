#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

labs_repo="${NETWORK_LABS_PATH:-${repo_root}/../network-labs}"

if [[ ! -f "${labs_repo}/current-lab/metadata.nix" ]]; then
  echo "FAIL FS-380 active-lab multi-uplink regression: missing network-labs current-lab at ${labs_repo}" >&2
  exit 1
fi

nix_eval_true_or_fail "FS-380 active-lab multi-uplink WAN attachment" \
  env REPO_ROOT="${repo_root}" NETWORK_LABS_PATH="${labs_repo}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          labsRepo = builtins.getEnv "NETWORK_LABS_PATH";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          system = "x86_64-linux";
          metadata = import (labsRepo + "/current-lab/metadata.nix");
          cpmNixosOut = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
            inputPath = labsRepo + "/current-lab/intent-s-router-nixos.nix";
            inventoryPath = labsRepo + "/current-lab/inventory-s-router-nixos.nix";
            validateForwardingModel = false;
            validateRuntimeModel = false;
          };
          cpmClientsOut = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuildFromPaths {
            inputPath = labsRepo + "/current-lab/intent-s-router-test-clients.nix";
            inventoryPath = labsRepo + "/current-lab/inventory-s-router-test-clients.nix";
            validateForwardingModel = false;
            validateRuntimeModel = false;
          };
          nixosModule = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-nixos";
            cpm = cpmNixosOut;
            selectorFile = "tests/test-fs380-hds020-sds010-sms050-active-lab-multi-uplink.sh";
          };
          clientsModule = flake.lib.renderer.hostModule {
            inherit lib system;
            hostName = "s-router-test-clients";
            cpm = cpmClientsOut;
            selectorFile = "tests/test-fs380-hds020-sds010-sms050-active-lab-multi-uplink.sh";
          };
          nixosEvaluated = lib.nixosSystem {
            inherit system;
            modules = [ nixosModule ];
          };
          clientsEvaluated = lib.nixosSystem {
            inherit system;
            modules = [ clientsModule ];
          };
          downstreamSelectorNetworks =
            nixosEvaluated.config.containers.downstream-selector.config.systemd.network.networks;
          upstreamSelectorNetworks =
            nixosEvaluated.config.containers.upstream-selector.config.systemd.network.networks;
          downstreamP1 = downstreamSelectorNetworks."10-p1" or { };
          downstreamP1Routes = downstreamP1.routes or [ ];
          downstreamP1Rules = downstreamP1.routingPolicyRules or [ ];
          downstreamInternetDefaultRoute = lib.findFirst
            (
              route:
                (route.Destination or null) == "0.0.0.0/0"
                && (route.Gateway or null) == "10.10.0.3"
                && builtins.isInt (route.Table or null)
            )
            null
            downstreamP1Routes;
          downstreamInternetTable =
            if downstreamInternetDefaultRoute == null
            then null
            else downstreamInternetDefaultRoute.Table;
          downstreamClientIngressRules = lib.filter
            (
              rule:
                (rule.Family or null) == "ipv4"
                && (rule.IncomingInterface or null) == "p0"
                && (rule.From or null) == "10.20.20.0/24"
            )
            downstreamP1Rules;
          downstreamClientIngressUsesInternetTable =
            builtins.any (rule: (rule.Table or null) == downstreamInternetTable) downstreamClientIngressRules;
          downstreamClientIngressUsesWrongTable =
            builtins.any
              (
                rule:
                  builtins.isInt (rule.Table or null)
                  && (rule.Table or null) != downstreamInternetTable
                  && (rule.Table or null) != 254
              )
              downstreamClientIngressRules;
          allUpstreamRoutes = lib.concatLists (
            map (name: (upstreamSelectorNetworks.${name} or { }).routes or [ ])
              (builtins.attrNames upstreamSelectorNetworks)
          );
          allUpstreamRules = lib.concatLists (
            map (name: (upstreamSelectorNetworks.${name} or { }).routingPolicyRules or [ ])
              (builtins.attrNames upstreamSelectorNetworks)
          );
          upstreamTableForIngress =
            ifName:
            let
              matches = lib.filter
                (
                  rule:
                    ((rule.Family or null) == "ipv4" || (rule.Family or null) == "both")
                    && (rule.IncomingInterface or null) == ifName
                    && builtins.isInt (rule.Table or null)
                    && (rule.Table or null) != 254
                )
                allUpstreamRules;
            in
              if matches == [ ] then null else (builtins.head matches).Table;
          upstreamP0Table = upstreamTableForIngress "p0";
          upstreamP1Table = upstreamTableForIngress "p1";
          upstreamP2Table = upstreamTableForIngress "p2";
          upstreamHasRoute =
            destination: gateway: table:
            builtins.any
              (
                route:
                  (route.Destination or null) == destination
                  && (route.Gateway or null) == gateway
                  && (route.Table or null) == table
              )
              allUpstreamRoutes;
          netdevs = nixosEvaluated.config.systemd.network.netdevs or { };
          networks = nixosEvaluated.config.systemd.network.networks or { };
          eth0Vlans = networks."20-eth0".networkConfig.VLAN or [ ];
          clientHostContainers = builtins.attrNames (clientsEvaluated.config.containers or { });
          controlPlane = builtins.fromJSON clientsEvaluated.config.environment.etc."network-artifacts/control-plane.json".text;
          renderedClientHost = builtins.fromJSON clientsEvaluated.config.environment.etc."network-artifacts/rendered-host.json".text;
          renderedNixosHost = builtins.fromJSON nixosEvaluated.config.environment.etc."network-artifacts/rendered-host.json".text;
          testClientsHost = controlPlane.deploymentHosts."s-router-test-clients" or { };
          emulatedIspNetworks = nixosEvaluated.config.containers.emulated-isp.config.systemd.network.networks or { };
          emulatedIspRendered = renderedNixosHost.containers."emulated-isp" or { };
          emulatedIspVethNames = builtins.attrNames (emulatedIspRendered.extraVeths or { });
          require = cond: msg: if cond then true else throw msg;
          selected =
            (
              (metadata.layer or "") == "SIT"
              && (metadata.selector or "") == "FS-380-HDS-020-SDS-010"
            )
            || (
              (metadata.layer or "") == "SMT"
              && (metadata.selector or "") == "internet-mode-verification"
            )
            || ((metadata.traceId or "") == "FS-380-HDS-020-SDS-010-SMS-050");
        in
          require selected
            "network-labs current-lab must be selected to SIT FS-380-HDS-020-SDS-010 or SMT internet-mode-verification"
          && require (builtins.hasAttr "11-eth0.4" netdevs)
            "s-router-nixos must emit VLAN4 netdev for the first explicit internet uplink"
          && require (builtins.hasAttr "11-eth0.5" netdevs)
            "s-router-nixos must emit VLAN5 netdev for the second explicit internet uplink"
          && require (builtins.elem "eth0.4" eth0Vlans && builtins.elem "eth0.5" eth0Vlans)
            "s-router-nixos parent eth0 must retain both internet VLAN children"
          && require ((testClientsHost.accessHandoff.kind or null) == "pppoe")
            "s-router-test-clients artifact must preserve deploymentHosts.s-router-test-clients.accessHandoff.kind"
          && require ((testClientsHost.accessHandoff.server or null) == "emulated-isp")
            "s-router-test-clients artifact must preserve deploymentHosts.s-router-test-clients.accessHandoff.server"
          && require (clientHostContainers == [ ])
            "s-router-test-clients must not render router fabric containers"
          && require (renderedClientHost.selectedUnits == [ ])
            "s-router-test-clients rendered artifact must preserve empty router unit selection"
          && require (builtins.all (name: builtins.hasAttr name emulatedIspNetworks) [ "10-p0" "10-u0" "10-u1" ])
            "emulated-isp must render the p0 fabric ingress and u0/u1 WAN uplink network units"
          && require (!(builtins.hasAttr "10-core-up-egress" emulatedIspNetworks))
            "emulated-isp must not materialize unnamed CPM core-egress audit surface as a networkd unit"
          && require (builtins.length emulatedIspVethNames == 3)
            "emulated-isp must only materialize p0 plus u0/u1 veths, not a synthetic core-egress veth"
          && require (downstreamInternetTable != null)
            "downstream-selector p1 must emit the explicit internet default route in a policy table"
          && require downstreamClientIngressUsesInternetTable
            "downstream-selector traffic entering from client-edge on p0 must select the same table that contains the p1 internet default route"
          && require (!downstreamClientIngressUsesWrongTable)
            "downstream-selector must not send client-edge ingress traffic to a different non-main table than the p1 internet default route"
          && require (upstreamP0Table != null && upstreamP1Table != null && upstreamP2Table != null)
            "upstream-selector must emit policy tables for p0, p1, and p2"
          && require (upstreamHasRoute "10.20.20.0/24" "10.10.0.6" upstreamP0Table)
            "upstream-selector p0 policy table must return client tenant traffic via p1"
          && require (upstreamHasRoute "10.20.20.0/24" "10.10.0.8" upstreamP0Table)
            "upstream-selector p0 policy table must return client tenant traffic via p2"
          && require (upstreamHasRoute "0.0.0.0/0" "10.10.0.4" upstreamP1Table)
            "upstream-selector p1 policy table must forward client internet traffic via p0"
          && require (upstreamHasRoute "0.0.0.0/0" "10.10.0.4" upstreamP2Table)
            "upstream-selector p2 policy table must forward client internet traffic via p0"
      '

missing_class_out="$(mktemp)"
missing_class_err="$(mktemp)"
trap 'rm -f "${missing_class_out}" "${missing_class_err}"' EXIT

echo "--- Seeded negative: missing CPM interfaceClass fails closed ---"
if env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      common = import (repoRoot + "/s88/Unit/mapping/runtime-targets/interfaces/common.nix") { inherit lib; };
      normalize = import (repoRoot + "/s88/Unit/mapping/runtime-targets/interfaces/normalize.nix") {
        inherit lib common;
        runtimeContext = {
          emittedInterfacesForUnit = _: { };
          runtimeTargetForUnit = _: { };
        };
        forwarding = {
          semanticInterfaceForUnit = _: {
            kind = "p2p";
          };
        };
        renderedNames = {
          renderedInterfaceNamesForUnit = _: { p0 = "p0"; };
        };
        hostBridge = {
          hostBridgeIdentityForInterface = _: null;
        };
      };
      result = normalize.normalizedInterfaceForUnit {
        cpm = { };
        unitName = "upstream-selector";
        ifName = "p0";
        renderedIfName = "p0";
        file = "tests/test-fs380-hds020-sds010-sms050-active-lab-multi-uplink.sh";
        iface = {
          sourceKind = "p2p";
          backingRef = {
            name = "p2p-policy-upstream-selector";
            kind = "p2p";
            uplinks = [ "internet-vlan4" "internet-vlan5" ];
          };
        };
      };
    in
      builtins.deepSeq result true
  ' >"${missing_class_out}" 2>"${missing_class_err}"; then
  echo "FAIL: renderer accepted CPM interface data without interfaceClass" >&2
  cat "${missing_class_out}" >&2
  exit 1
fi

grep -Fq "missing CPM interfaceClass" "${missing_class_err}" \
  || fail "FAIL: missing interfaceClass diagnostic did not name the CPM contract"
grep -Fq "must not reconstruct interface" "${missing_class_err}" \
  || fail "FAIL: missing interfaceClass diagnostic did not reject renderer inference"
echo "PASS: missing CPM interfaceClass is rejected"

echo "PASS FS-380 active-lab multi-uplink WAN attachment"
