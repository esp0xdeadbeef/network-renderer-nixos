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
    inherit lib pkgs containerName renderedModel alarmModel;
  };

  containerNetworkRender = import ../container-networks.nix {
    inherit lib uplinks wanUplinkName;
    containerModel = renderedModel;
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

  accessServices =
    if (renderedModel.roleName or null) == "access" then
      import ../../access/render/default.nix {
        inherit lib pkgs;
        containerModel = renderedModel;
      }
    else
      { };

  dnsServices = import ./dns-services.nix { inherit lib pkgs renderedModel; };
  mdnsServices = import ./mdns-services.nix { inherit lib pkgs renderedModel; };
  bgpServices = import ./bgp-services.nix { inherit lib renderedModel; };
in
{
  imports = base.imports;

  config = lib.mkMerge [
    base.commonRouterConfig
    {
      networking.hostName = base.resolvedHostName;
      systemd.network.networks = containerNetworkRender.networks;
      warnings = base.warningMessages;
    }
    networkManager.config
    delegatedRoutes.config
    (lib.optionalAttrs ((containerNetworkRender.ipv6AcceptRAInterfaces or [ ]) != [ ]) {
      boot.kernel.sysctl = import ./module/ipv6-ra-sysctls.nix {
        inherit lib;
        interfaces = containerNetworkRender.ipv6AcceptRAInterfaces or [ ];
      };
    })
    interfaceRenames.config
    accessServices
    dnsServices
    mdnsServices
    bgpServices
    (lib.optionalAttrs firewallArg.enable {
      networking.nftables.enable = true;
      networking.nftables.ruleset = firewallArg.ruleset;
    })
  ];
}
