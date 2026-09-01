{
  lib,
  containerName,
  renderedModel,
  firewallArg,
  alarmModel,
  uplinks,
  wanUplinkName,
}:

{
  lib,
  pkgs,
  ...
}:

let
  base = import ./module/base.nix {
    inherit
      lib
      pkgs
      containerName
      renderedModel
      alarmModel
      ;
  };

  containerNetworkRender = import ../container-networks.nix {
    inherit lib uplinks wanUplinkName;
    containerModel = renderedModel;
    forwardingIntent =
      (firewallArg.lookup or { }).forwardingIntent or firewallArg.forwardingIntent or null;
    firewallRuleset = firewallArg.ruleset or null;
  };

  interfaceRenames = import ./module/interface-renames.nix {
    inherit lib pkgs renderedModel;
  };

  networkManager = import ./module/network-manager.nix {
    inherit lib pkgs renderedModel;
  };

  delegatedRoutes = import ./module/delegated-routes.nix {
    inherit lib pkgs;
    dynamicDelegatedRoutes = containerNetworkRender.dynamicDelegatedRoutes or [ ];
  };

  staticProviderRoutes = import ./module/static-provider-routes.nix {
    inherit lib pkgs;
    staticProviderRoutes = containerNetworkRender.staticProviderRoutes or [ ];
    staticProviderPolicyRules = containerNetworkRender.staticProviderPolicyRules or [ ];
  };

  dynamicForwarding = import ./module/dynamic-forwarding.nix {
    inherit lib pkgs;
    dynamicSourceForwardRules = containerNetworkRender.dynamicSourceForwardRules or [ ];
    tableName = containerNetworkRender.firewallTableName or "router";
  };

  dynamicDestinationForwarding = import ./module/dynamic-destination-forwarding.nix {
    inherit lib pkgs;
    dynamicDestinationForwardRules = containerNetworkRender.dynamicDestinationForwardRules or [ ];
  };

  dynamicPolicyRules = import ./module/dynamic-policy-rules.nix {
    inherit lib pkgs;
    dynamicPolicySourceRules = containerNetworkRender.dynamicPolicySourceRules or [ ];
  };

  edgeServices =
    if renderedModel.enableEdgeServices or false then
      import ../../access/render/default.nix {
        inherit lib pkgs;
        containerModel = renderedModel;
      }
    else
      { };

  dnsServices = import ./dns-services.nix {
    inherit lib pkgs renderedModel;
    forwardingIntent =
      (firewallArg.lookup or { }).forwardingIntent or firewallArg.forwardingIntent or { };
  };
  mdnsServices = import ./mdns-services.nix { inherit lib pkgs renderedModel; };
  bgpServices = import ./bgp-services.nix { inherit lib renderedModel; };
  pppoeServices = import ./module/pppoe.nix {
    inherit
      lib
      pkgs
      renderedModel
      uplinks
      wanUplinkName
      ;
  };
  noClientIdDhcp = import ./module/no-clientid-dhcp.nix {
    inherit
      lib
      pkgs
      renderedModel
      uplinks
      wanUplinkName
      ;
  };
in
{
  imports = base.imports;

  config = lib.mkMerge [
    base.commonRouterConfig
    {
      networking.hostName = base.resolvedHostName;
      systemd.network.netdevs = containerNetworkRender.netdevs or { };
      systemd.network.networks = containerNetworkRender.networks;
      warnings = base.warningMessages;
    }
    networkManager.config
    delegatedRoutes.config
    staticProviderRoutes.config
    dynamicForwarding.config
    dynamicDestinationForwarding.config
    dynamicPolicyRules.config
    (lib.optionalAttrs ((containerNetworkRender.ipv6AcceptRAInterfaces or [ ]) != [ ]) {
      boot.kernel.sysctl = import ./module/ipv6-ra-sysctls.nix {
        inherit lib;
        interfaces = containerNetworkRender.ipv6AcceptRAInterfaces or [ ];
      };
    })
    (lib.optionalAttrs (containerNetworkRender.hasMultipathRoute or false) {
      boot.kernel.sysctl = {

        "net.ipv4.fib_multipath_use_neigh" = 1;
        "net.ipv4.fib_multipath_hash_policy" = 1;
        "net.ipv6.fib_multipath_hash_policy" = 1;

        "net.ipv4.neigh.default.base_reachable_time_ms" = 3000;
        "net.ipv4.neigh.default.delay_first_probe_time" = 1;
        "net.ipv4.neigh.default.gc_stale_time" = 15;
        "net.ipv6.neigh.default.base_reachable_time_ms" = 3000;
        "net.ipv6.neigh.default.delay_first_probe_time" = 1;
        "net.ipv6.neigh.default.gc_stale_time" = 15;
      };
    })
    interfaceRenames.config
    edgeServices
    dnsServices
    mdnsServices
    bgpServices
    pppoeServices.config
    noClientIdDhcp.config
    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
