{
  config,
  lib,
  hostContext,
  globalInventory,
  activeRoleNames ? [ ],
  activeRoles ? { },
  s88Role ? null,
  ...
}:

let
  sortedAttrNames = attrs:
    lib.sort builtins.lessThan (builtins.attrNames attrs);

  deploymentHostName =
    if hostContext ? deploymentHostName && builtins.isString hostContext.deploymentHostName then
      hostContext.deploymentHostName
    else
      config.networking.hostName;

  deploymentHost =
    if hostContext ? deploymentHost
      && builtins.isAttrs hostContext.deploymentHost
      && hostContext.deploymentHost != { }
    then
      hostContext.deploymentHost
    else if globalInventory ? deployment
      && builtins.isAttrs globalInventory.deployment
      && globalInventory.deployment ? hosts
      && builtins.isAttrs globalInventory.deployment.hosts
      && builtins.hasAttr deploymentHostName globalInventory.deployment.hosts
    then
      globalInventory.deployment.hosts.${deploymentHostName}
    else
      { };

  renderedHostNetwork = import ../../../lib/render-host-network.nix {
    inherit lib;
    inventory = globalInventory;
    hostName = deploymentHostName;
  };

  effectiveActiveRoles =
    if activeRoles != { } then
      activeRoles
    else if s88Role != null then
      { default = s88Role; }
    else
      { };

  effectiveActiveRoleNames =
    if activeRoleNames != [ ] then
      activeRoleNames
    else
      sortedAttrNames effectiveActiveRoles;

  roleExtra =
    lib.foldl'
      (acc: roleName:
        let
          role = effectiveActiveRoles.${roleName};
          extra =
            if role ? hostProfilePath && role.hostProfilePath != null then
              import role.hostProfilePath {
                inherit
                  lib
                  config
                  globalInventory
                  hostContext
                  deploymentHostName
                  deploymentHost;
              }
            else
              {
                netdevs = { };
                networks = { };
              };
        in
        {
          netdevs = acc.netdevs // (extra.netdevs or { });
          networks = acc.networks // (extra.networks or { });
        })
      {
        netdevs = { };
        networks = { };
      }
      effectiveActiveRoleNames;
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs =
    renderedHostNetwork.netdevs
    // (roleExtra.netdevs or { });

  systemd.network.networks =
    renderedHostNetwork.networks
    // (roleExtra.networks or { });
}
