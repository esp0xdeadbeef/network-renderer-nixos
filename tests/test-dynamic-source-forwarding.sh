#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
      runtimeTarget = {
        forwardingIntent = {
          mode = "explicit-selector-forwarding";
          rules = [
            {
              action = "accept";
              fromInterface = "core-nebula";
              toInterface = "core";
              sourceFiles = [ "/run/secrets/access-node-ipv6-prefix-hostile" ];
              family = 6;
              relationId = "runtime-routed-prefix-public-egress";
            }
            {
              action = "accept";
              fromInterface = "policy-dmz-wan";
              toInterface = "core";
              sourceFiles = [ "/run/secrets/access-node-ipv6-prefix-hostile" ];
              sourcePrefixes = [
                {
                  family = 4;
                  prefix = "10.20.70.0/24";
                }
              ];
              family = 6;
              relationId = "runtime-routed-prefix-public-egress";
            }
          ];
        };
      };
      forwardingIntent =
        import (repoRoot + "/s88/ControlModule/firewall/lookup/forwarding-intent.nix") {
          inherit lib runtimeTarget;
          interfaces = {
            core-nebula.containerInterfaceName = "core-nebula";
            policy-dmz-wan.containerInterfaceName = "policy-dmz-wan";
            core.containerInterfaceName = "core";
          };
        };
      firewallRules =
        import (repoRoot + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
          inherit lib forwardingIntent;
          escapeComment = value: value;
          renderTrafficType = _: [ "" ];
        };
      render =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib forwardingIntent;
          uplinks = { };
          wanUplinkName = null;
          containerModel = {
            interfaces = {
              core-nebula = {
                containerInterfaceName = "core-nebula";
                addresses = [ "fd42:dead:cafe:1000::b/127" ];
              };
              core = {
                containerInterfaceName = "core";
                addresses = [ "10.80.0.5/31" "fd42:dead:cafe:1000::5/127" ];
              };
            };
          };
        };
      policyRouteRender =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          forwardingIntent = runtimeTarget.forwardingIntent;
          uplinks = { };
          wanUplinkName = null;
          containerModel = {
            networkBehavior.isUpstreamSelector = true;
            interfaces = {
              core = {
                containerInterfaceName = "core";
                interfaceClass.coreFacing = true;
                addresses = [ "fd42:dead:cafe:1000::5/127" ];
                routes = [
                  {
                    family = 6;
                    sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
                    via6 = "fd42:dead:cafe:1000::4";
                    intent.kind = "runtime-routed-prefix-public-egress";
                  }
                ];
              };
              policy-wan = {
                containerInterfaceName = "policy-wan";
                interfaceClass.exitFacing = true;
                sourceKind = "wan";
                addresses = [ "fd42:dead:cafe:1900::2/127" ];
                routes = [
                  {
                    family = 6;
                    dst = "::/0";
                    via6 = "fd42:dead:cafe:1900::3";
                  }
                ];
              };
              policy-dmz-wan = {
                containerInterfaceName = "policy-dmz-wan";
                interfaceClass.exitFacing = true;
                sourceKind = "wan";
                addresses = [ "10.80.0.17/31" "fd42:dead:cafe:1000::11/127" ];
                backingRef.lane = {
                  access = "router-access-dmz";
                  uplink = "wan";
                };
                routes = [
                  {
                    family = 6;
                    dst = "::/0";
                    via6 = "fd42:dead:cafe:1000::4";
                    policyOnly = true;
                    reason = "policy-derived-default";
                  }
                ];
              };
              core-nebula = {
                containerInterfaceName = "core-nebula";
                interfaceClass.coreFacing = true;
                addresses = [ "fd42:dead:cafe:1000::b/127" ];
                routes = [
                  {
                    proto = "overlay";
                    family = 6;
                    sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
                    via6 = "fd42:dead:cafe:1000::a";
                    intent.kind = "runtime-routed-prefix-return";
                  }
                ];
              };
            };
          };
        };
      dynamicForwarding =
        import (repoRoot + "/s88/ControlModule/render/containers/module/dynamic-forwarding.nix") {
          inherit lib pkgs;
          dynamicSourceForwardRules = render.dynamicSourceForwardRules;
        };
      service = dynamicForwarding.config.systemd.services."s88-dynamic-forward-0" or null;
      policyRouteRules =
        lib.concatMap
          (network: network.routingPolicyRules or [ ])
          (builtins.attrValues policyRouteRender.networks);
      overlayRouteRender =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          uplinks = { };
          wanUplinkName = null;
          containerModel = {
            interfaces = {
              overlay-east-west = {
                containerInterfaceName = "nebula1";
                sourceKind = "overlay";
                addresses = [ "fd42:dead:beef:ee::3/128" ];
                routes = [
                  {
                    proto = "overlay";
                    family = 6;
                    sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
                    intent.kind = "runtime-routed-prefix-return";
                    metric = 50;
                  }
                ];
              };
            };
          };
        };
      downstreamReturnRender =
        import (repoRoot + "/s88/ControlModule/render/container-networks.nix") {
          inherit lib;
          forwardingIntent.rules = [
            { action = "accept"; fromInterface = "access-hostile"; toInterface = "policy-hostile"; }
            { action = "accept"; fromInterface = "policy-hostile"; toInterface = "access-hostile"; }
          ];
          uplinks = { };
          wanUplinkName = null;
          containerModel = {
            networkBehavior.isDownstreamSelector = true;
            interfaces = {
              access-hostile = {
                containerInterfaceName = "access-hostile";
                addresses = [ "fd42:dead:beef:1000::7/127" ];
                routes = [
                  {
                    family = 6;
                    sourceFile = "/run/secrets/access-node-ipv6-prefix-hostile";
                    via6 = "fd42:dead:beef:1000::6";
                    intent.kind = "runtime-routed-prefix-return";
                  }
                ];
              };
              policy-hostile = {
                containerInterfaceName = "policy-hostile";
                addresses = [ "fd42:dead:beef:1000::18/127" ];
                routes = [
                  {
                    family = 6;
                    dst = "::/0";
                    via6 = "fd42:dead:beef:1000::19";
                    policyOnly = true;
                    reason = "policy-derived-default";
                  }
                ];
              };
            };
          };
        };
      ok =
        builtins.any
        (rule:
          rule.action == "accept"
          && rule.comment == "runtime-routed-prefix-public-egress"
          && rule.family == 6
          && rule.inIf == "core-nebula"
          && rule.outIf == "core"
          && rule.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile")
        render.dynamicSourceForwardRules
      && builtins.any
        (rule:
          rule.action == "accept"
          && rule.comment == "runtime-routed-prefix-public-egress"
          && rule.family == 6
          && rule.inIf == "policy-dmz-wan"
          && rule.outIf == "core"
          && rule.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile")
        render.dynamicSourceForwardRules
      && builtins.elem
        "iifname \"policy-dmz-wan\" oifname \"core\" ip saddr 10.20.70.0/24 accept comment \"runtime-routed-prefix-public-egress\""
        firewallRules
      && service != null
      && builtins.match ".*ip6 saddr.*" service.script != null
      && builtins.any
        (route:
          route.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile"
          && route.interfaceName == "core-nebula"
          && route.gateway == "fd42:dead:cafe:1000::a"
          && route.table == 2000)
        policyRouteRender.dynamicDelegatedRoutes
      && builtins.any
        (route:
          route.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile"
          && route.interfaceName == "core-nebula"
          && route.gateway == "fd42:dead:cafe:1000::a"
          && route.table == 2002)
        policyRouteRender.dynamicDelegatedRoutes
      && builtins.any
        (rule:
          rule.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile"
          && rule.interfaceName == "policy-dmz-wan"
          && rule.table != 254)
        policyRouteRender.dynamicPolicySourceRules
      && builtins.any
          (rule:
          (rule.From or null) == "10.20.70.0/24"
          && (rule.IncomingInterface or null) == "policy-dmz-wan"
          && (rule.Table or null) == 2002)
        policyRouteRules
      && !(builtins.any
        (route:
          route.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile"
          && route.interfaceName == "core"
          && route.table == 2000)
        policyRouteRender.dynamicDelegatedRoutes)
      && overlayRouteRender.dynamicDelegatedRoutes == [ ]
      && builtins.any
        (route:
          route.sourceFile == "/run/secrets/access-node-ipv6-prefix-hostile"
          && route.interfaceName == "access-hostile"
          && route.gateway == "fd42:dead:beef:1000::6"
          && route.table == 2001)
        downstreamReturnRender.dynamicDelegatedRoutes
      ;
    in
      if ok then true else throw ("dynamic-source-forwarding failed: " + builtins.toJSON {
        inherit firewallRules;
        dynamicSourceForwardRules = render.dynamicSourceForwardRules;
        dynamicPolicySourceRules = policyRouteRender.dynamicPolicySourceRules;
        inherit policyRouteRules;
        dynamicDelegatedRoutes = policyRouteRender.dynamicDelegatedRoutes;
        downstreamDynamicDelegatedRoutes = downstreamReturnRender.dynamicDelegatedRoutes;
        overlayDynamicDelegatedRoutes = overlayRouteRender.dynamicDelegatedRoutes;
        servicePresent = service != null;
      })
  ' >/dev/null

echo "PASS dynamic-source-forwarding"
