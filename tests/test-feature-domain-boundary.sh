#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-001
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-CMC-001-001
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nix_eval_true_or_fail \
  feature-domain-boundary \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };

        dnsRendered =
          import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
            inherit lib pkgs;
            renderedModel = {
              runtimeTarget = {
                services.dns = {
                  listen = [ "10.53.0.1" ];
                  allowFrom = [ "10.53.0.0/24" ];
                  forwarders = [ "1.1.1.1" ];
                  localZones = [ { name = "feature."; } ];
                  localRecords = [
                    {
                      name = "node.feature.";
                      a = [ "10.53.0.10" ];
                    }
                  ];
                  outgoingInterfaces = [ "10.99.0.2" ];
                  deniedResolverCidrs = [ "1.1.1.1/32" ];
                };
                stateContracts.persistence.dhcp4Leases = [
                  {
                    service = "dhcp4";
                    id = "unrelated";
                    path = "/persist/network/state/unrelated";
                  }
                ];
              };
              interfaces.overlay-east-west = {
                sourceKind = "overlay";
                renderedIfName = "overlay-west";
              };
            };
          };

        advertisementModel =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              interfaces.tenant-client = {
                interfaceName = "tenant-client";
                sourceKind = "tenant";
                addresses = [ "10.20.20.1/24" ];
              };
              runtimeTarget = {
                advertisements.dhcp4 = [
                  {
                    id = "client-v4";
                    interface = "tenant-client";
                    tenant = "client";
                    subnet = "10.20.20.0/24";
                    pool = "10.20.20.100 - 10.20.20.199";
                    router = "10.20.20.1";
                    dnsServers = [ "10.20.20.1" ];
                  }
                ];
                services.dns.listen = [ "10.53.0.1" ];
                stateContracts.persistence.dhcp4Leases = [
                  {
                    service = "dhcp4";
                    id = "client-v4";
                    kind = "lease-state";
                    mode = "persistent";
                    required = true;
                    interface = "tenant-client";
                    tenant = "client";
                    source = "inventory-realization";
                    path = "/persist/network/state/dhcp4/router-access-client/client-v4";
                  }
                ];
              };
            };
          };

        overlayRender =
          import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
            inherit lib;
            uplinks = { };
            wanUplinkName = null;
            containerModel = {
              externalValidationDelegatedPrefixSources = {
                "fd42:dead:feed:70::/64" = "/run/secrets/access-node-ipv6-prefix-branch-hostile";
              };
              interfaces.overlay-east-west = {
                containerInterfaceName = "overlay-west";
                sourceKind = "overlay";
                addresses = [ "fd42:dead:beef:ee::3/128" ];
                routes = [
                  {
                    dst = "fd42:dead:feed:70::/64";
                    proto = "overlay";
                    overlay = "east-west";
                    via6 = "fd42:dead:beef:ee::2";
                  }
                ];
              };
            };
          };

        dnsServiceNames = builtins.attrNames (dnsRendered.services or { });
        dnsSystemdServiceNames = builtins.attrNames ((dnsRendered.systemd or { }).services or { });
        dhcp4Scope = builtins.head advertisementModel.dhcp4Scopes;
      in
        if
          builtins.elem "unbound" dnsServiceNames
          && !(builtins.elem "kea" dnsServiceNames)
          && !(builtins.elem "kea-dhcp4-client-v4" dnsSystemdServiceNames)
          && !((dnsRendered.systemd or { }) ? network)
          && dhcp4Scope.leaseState.path == "/persist/network/state/dhcp4/router-access-client/client-v4"
          && overlayRender.dynamicDelegatedRoutes == [ ]
        then
          true
        else
          throw "feature-domain-boundary failed: a feature module consumed or emitted data outside its declared feature domain"
    '

pass "feature-domain-boundary"
