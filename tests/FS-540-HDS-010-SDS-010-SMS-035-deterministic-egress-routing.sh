#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-035
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
      policyRoutingAllocation = {
        source = "control-plane-model";
        tableId = 1002;
        tableRulePriority = 1002;
      };
      runtimeTarget = {
        runtimeOriginEgress = {
          enabled = true;
          source = "dns-service";
          policyRoutingRequired = true;
          uplinks = [ "isp-primary" ];
          policyRouting = {
            source = "control-plane-model";
            selectedUplink = "isp-primary";
            selectedInterface = "isp-primary";
            runtimeIfName = "wan0";
            tableId = 1002;
            rulePriority = 1002;
            firewallMark = 1002;
          };
        };
        services.dns = {
          recursionMode = "iterative";
          listen = [ "192.0.2.1" "2001:db8::1" ];
          allowFrom = [ "192.0.2.0/24" "2001:db8::/64" ];
          forwarders = [ ];
          reproducibilityWarnings = [ ];
        };
      };
      interfaces = {
        isp-primary = {
          sourceKind = "wan";
          runtimeIfName = "wan0";
          renderedIfName = "wan0";
          dynamicAddressing.ipv6 = {
            enable = true;
            method = "slaac";
            acceptRA = true;
          };
          inherit policyRoutingAllocation;
        };
      };
      common = import (repoRoot + "/s88/ControlModule/render/container-networks/common.nix") { inherit lib; };
      dynamicWan = import (repoRoot + "/s88/ControlModule/render/container-networks/dynamic-wan.nix") {
        inherit lib common;
        uplinks = { };
        wanUplinkName = null;
      };
      render = target: ifaces:
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs;
          renderedModel = {
            runtimeTarget = target;
            interfaces = ifaces;
          };
          forwardingIntent = { };
        };
      rendered = render runtimeTarget interfaces;
      rules = rendered.systemd.network.networks."10-wan0".routingPolicyRules;
      nftScript = rendered.systemd.services.nft-allow-dns-service.script;
      ipv6AcceptRAConfig = dynamicWan.mkDynamicWanIpv6AcceptRAConfig interfaces.isp-primary null;
      hasRule = family:
        builtins.any
          (rule:
            rule == {
              Family = family;
              FirewallMark = 1002;
              Priority = 1002;
              Table = 1002;
            })
          rules;
      hasScopedResolverRule = family: protocol:
        builtins.any
          (rule:
            rule == {
              Family = family;
              User = "unbound";
              IPProtocol = protocol;
              DestinationPort = 53;
              Priority = 1002;
              Table = 1002;
            })
          rules;
      hasNoProcessWideResolverIdentityRule =
        builtins.all
          (rule:
            !(rule ? User)
            || (
              (rule.User or null) == "unbound"
              && builtins.elem (rule.IPProtocol or null) [ "udp" "tcp" ]
              && (rule.DestinationPort or null) == 53
            ))
          rules;
      missingPolicyTarget = runtimeTarget // {
        runtimeOriginEgress = builtins.removeAttrs runtimeTarget.runtimeOriginEgress [ "policyRouting" ];
      };
      divergentMarkTarget = runtimeTarget // {
        runtimeOriginEgress = runtimeTarget.runtimeOriginEgress // {
          policyRouting = runtimeTarget.runtimeOriginEgress.policyRouting // { firewallMark = 1003; };
        };
      };
      missingPolicy = builtins.tryEval (
        builtins.deepSeq (render missingPolicyTarget interfaces).systemd.network.networks true
      );
      divergentAllocation = builtins.tryEval (
        builtins.deepSeq
          (render divergentMarkTarget (interfaces // {
            isp-primary = interfaces.isp-primary // {
              policyRoutingAllocation = policyRoutingAllocation // { tableId = 1003; };
            };
          })).systemd.network.networks
          true
      );
    in
      hasRule "ipv4"
      && hasRule "ipv6"
      && hasScopedResolverRule "ipv4" "udp"
      && hasScopedResolverRule "ipv4" "tcp"
      && hasScopedResolverRule "ipv6" "udp"
      && hasScopedResolverRule "ipv6" "tcp"
      && hasNoProcessWideResolverIdentityRule
      && builtins.length rules == 6
      && lib.hasInfix "type route hook output priority mangle" nftScript
      && lib.hasInfix "udp dport 53 meta mark set 1002" nftScript
      && lib.hasInfix "tcp dport 53 meta mark set 1002" nftScript
      && lib.hasInfix "select-modeled-dns-egress" nftScript
      && ipv6AcceptRAConfig == { RouteTable = 1002; }
      && builtins.elem "nft-allow-dns-service.service" rendered.systemd.services.unbound.after
      && !missingPolicy.success
      && !divergentAllocation.success
  ' | grep -qx true

echo "PASS FS-540 deterministic iterative DNS egress routing materialization"
