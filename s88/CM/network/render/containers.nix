{
  lib,
  hostPlan,
  cpm,
  inventory,
}:

let
  nft = import ../roles/nftables.nix { inherit lib; };
  containerModel = import ./container-model.nix {
    inherit
      lib
      hostPlan
      ;
  };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  mkContainer =
    unitName:
    let
      model = containerModel.${unitName};

      nftRuleset =
        if model.roleName != null && builtins.hasAttr model.roleName nft then
          nft.${model.roleName} {
            wanIfs = model.wanInterfaceNames;
            lanIfs = model.lanInterfaceNames;
            inherit
              unitName
              cpm
              inventory
              ;
            roleName = model.roleName;
            runtimeTarget = model.runtimeTarget;
            interfaces = model.runtimeTarget.interfaces or { };
          }
        else
          null;
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        inherit (model)
          bindMounts
          allowedDevices
          extraVeths
          ;

        additionalCapabilities = lib.unique (
          [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ]
          ++ (model.additionalCapabilities or [ ])
        );

        specialArgs = {
          inherit
            unitName
            ;
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

            networking.hostName = unitName;
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
            systemd.network.networks = model.containerNetworks;
          };
      };
    };
in
builtins.listToAttrs (map mkContainer (sortedAttrNames containerModel))
