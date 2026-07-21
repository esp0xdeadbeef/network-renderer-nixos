#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
	"FS-540 canonical NixOS DNS materialization" \
	"${result_json}" \
	"${stderr_file}" \
	env REPO_ROOT="${repo_root}" \
	nix eval --impure --json --expr '
    let
      renderer = builtins.getFlake (toString (builtins.getEnv "REPO_ROOT"));
      system = builtins.currentSystem;
      trace = "FS-540-HDS-010-SDS-010-SMS-020";
      row = renderer.inputs.network-labs + "/GAMP/SMT/${trace}";
      cpm = renderer.inputs.network-control-plane-model.libBySystem.${system}.compileAndBuild {
        input = import (row + "/intent.nix");
        inventory = import (row + "/inventory-nixos.nix");
      };
      artifact = {
        kind = "network-control-plane-artifact";
        artifactIdentity = "${trace}-nixos-cpm";
        artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpm.control_plane_model);
        inherit (cpm) control_plane_model;
      };
      bundle = renderer.inputs.network-realization-model.lib.realize {
        input = artifact;
        requestScope = {
          kind = "complete-artifact";
          identity = "${trace}-nixos";
        };
        rootLockIdentity = "network-renderer-nixos-flake-lock";
        producerRevision = renderer.inputs.network-realization-model.rev;
      };
      canonical = renderer.libBySystem.${system}.renderer.canonical;
      validated = canonical.validateInput { inherit bundle; };
      evaluated = renderer.inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          (canonical.hostModule {
            inherit bundle;
            hostName = "s-router-nixos";
          })
          ({ ... }: {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          })
        ];
      };
      cfg = evaluated.config;
      access = cfg.containers.access-dns.config;
      core = cfg.containers.resolver-node.config;
      accessDns = access.services.unbound.settings;
      coreDns = core.services.unbound.settings;
      accessServer = accessDns.server;
      coreServer = coreDns.server;
      accessForwardZones = accessDns."forward-zone";
      coreForwardZones = coreDns."forward-zone";
      coreWan = core.systemd.network.networks."10-wan0";
      coreRules = coreWan.routingPolicyRules;
      hasRule = family: protocol:
        builtins.any
          (rule:
            (rule.Family or null) == family
            && (rule.User or null) == "unbound"
            && (rule.IPProtocol or null) == protocol
            && (rule.DestinationPort or null) == 53
            && (rule.Table or null) == 1002)
          coreRules;
      rawCpmRejected = !(builtins.tryEval (builtins.deepSeq (canonical.validateInput {
        bundle = cpm;
      }) true)).success;
      tamperedBundle = bundle // {
        network = bundle.network // {
          data = bundle.network.data // { rendererInventedDefault = true; };
        };
      };
      unvalidatedMutationRejected = !(builtins.tryEval (builtins.deepSeq (canonical.validateInput {
        bundle = tamperedBundle;
      }) true)).success;
      checks = {
        canonicalReleaseAccepted =
          bundle.validation.valid
          && validated.bundleIdentity == bundle.bundleIdentity;
        inherit rawCpmRejected unvalidatedMutationRejected;
        exactContainers = builtins.attrNames cfg.containers == [
          "access-dns"
          "downstream-selector"
          "policy"
          "resolver-node"
          "upstream-selector"
        ];
        accessListensOnlyOnLoopbackAndTenant = accessServer.interface == [
          "127.0.0.1"
          "::1"
          "10.2.28.1"
          "fd42:21c:50:0:0:0:0:1"
        ];
        accessForwardsOnlyToNamedCore = accessForwardZones == [
          {
            name = ".";
            "forward-addr" = [
              "10.2.255.6"
              "fd42:21c:fe:0:0:0:0:6"
            ];
          }
        ];
        accessAclIsRequesterOnly = accessServer."access-control" == [
          "127.0.0.0/8 allow"
          "::1/128 allow"
          "10.2.28.0/24 allow"
          "fd42:021c:50::/64 allow"
        ];
        coreIsIterative = coreForwardZones == [ ] && !(coreServer ? "outgoing-interface");
        coreListensOnlyOnInternalSurface = coreServer.interface == [
          "127.0.0.1"
          "::1"
          "10.2.255.6"
          "fd42:21c:fe:0:0:0:0:6"
        ];
        coreAclIsAccessResolverOnly = coreServer."access-control" == [
          "127.0.0.0/8 allow"
          "::1/128 allow"
          "10.2.28.1/32 allow"
          "fd42:21c:50:0:0:0:0:1/128 allow"
        ];
        coreDualStackDynamicEgress =
          coreWan.networkConfig.DHCP == "ipv4"
          && coreWan.networkConfig.IPv6AcceptRA == true
          && coreWan.dhcpV4Config.RouteTable == 1002
          && coreWan.ipv6AcceptRAConfig.RouteTable == 1002;
        coreDnsPolicyIsDualStackUdpTcp =
          hasRule "ipv4" "udp"
          && hasRule "ipv4" "tcp"
          && hasRule "ipv6" "udp"
          && hasRule "ipv6" "tcp";
        noPublicFallbackLiteral =
          let
            renderedDns = builtins.toJSON {
              inherit accessDns coreDns;
            };
          in
          builtins.match ".*(1[.]1[.]1[.]1|8[.]8[.]8[.]8|9[.]9[.]9[.]9|2606:4700).*" renderedDns == null;
      };
    in {
      inherit checks;
      ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
      failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
    }
  '

assert_json_checks_ok "FS-540 canonical NixOS DNS materialization" "${result_json}"
pass "FS-540 canonical NixOS DNS materialization and fail-closed boundary"
