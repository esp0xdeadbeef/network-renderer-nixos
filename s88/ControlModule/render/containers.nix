{
  lib,
  hostPlan,
  cpm,
  inventory,
}:

let
  firewall = import ../firewall/default.nix { inherit lib; };
  containerRuntime = import ../mapping/container-runtime.nix {
    inherit
      lib
      hostPlan
      ;
  };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  mkContainer =
    unitKey:
    let
      model = containerRuntime.${unitKey};

      containerNetworks = import ./container-networks.nix {
        inherit lib;
        containerModel = model;
        uplinks = hostPlan.uplinks or { };
        wanUplinkName = hostPlan.wanUplinkName or null;
      };

      nftRuleset = firewall {
        inherit
          cpm
          inventory
          ;
        unitKey = model.unitKey;
        unitName = model.unitName;
        roleName = model.roleName;
        runtimeTarget = model.runtimeTarget;
        interfaces = model.interfaces or { };
        wanIfs = model.wanInterfaceNames or [ ];
        lanIfs = model.lanInterfaceNames or [ ];
        uplinks = hostPlan.uplinks or { };
      };
    in
    {
      name = model.containerName;
      value = {
        autoStart = true;
        privateNetwork = true;

        inherit (model)
          bindMounts
          allowedDevices
          ;

        extraVeths = model.veths;

        additionalCapabilities = lib.unique (
          [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ]
          ++ (model.additionalCapabilities or [ ])
        );

        specialArgs = {
          unitKey = model.unitKey;
          unitName = model.unitName;
          deploymentHostName = model.deploymentHostName;
          runtimeTarget = model.runtimeTarget;
          controlPlaneOut = cpm;
          globalInventory = inventory;
          hostContext = model.hostContext;
          s88Role = model.roleConfig;
          s88RoleName = model.roleName;
        };

        config =
          { pkgs, ... }:
          {
            imports = [
              ../profiles/common-router.nix
            ]
            ++ lib.optionals (model.profilePath != null) [
              model.profilePath
            ];

            environment.systemPackages = with pkgs; [
              gron
              traceroute
            ];

            networking.hostName = model.containerName;
            networking.useNetworkd = true;
            systemd.network.enable = true;
            networking.useDHCP = false;
            networking.useHostResolvConf = lib.mkForce false;
            services.resolved.enable = lib.mkForce false;

            networking.nftables = lib.mkIf (nftRuleset != null) {
              enable = true;
              ruleset = nftRuleset;
            };

            system.stateVersion = lib.mkDefault "25.11";
            systemd.network.networks = containerNetworks;
          };
      };
    };
in
builtins.listToAttrs (map mkContainer (sortedAttrNames containerRuntime))
