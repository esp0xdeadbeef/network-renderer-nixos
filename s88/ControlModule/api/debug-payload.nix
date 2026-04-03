{
  lib,
  system,
  hostName,
  hostContext,
  intent,
  globalInventory,
  compilerOut,
  forwardingOut,
  controlPlaneOut,
  renderedHostNetwork,
  intentPath,
  inventoryPath,
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeDebug =
    raw: if !builtins.isAttrs raw then { } else builtins.removeAttrs raw [ "profilePath" ];

  sanitizeContainer =
    containerName: container:
    let
      specialArgs =
        if container ? specialArgs && builtins.isAttrs container.specialArgs then
          container.specialArgs
        else
          { };

      firewall =
        if specialArgs ? s88Firewall then
          let
            rawFirewall = specialArgs.s88Firewall;
          in
          if builtins.isAttrs rawFirewall then
            {
              enable = rawFirewall.enable or false;
              ruleset = if rawFirewall ? ruleset then rawFirewall.ruleset else null;
            }
          else if builtins.isString rawFirewall then
            {
              enable = rawFirewall != "";
              ruleset = rawFirewall;
            }
          else
            {
              enable = false;
              ruleset = null;
            }
        else
          {
            enable = false;
            ruleset = null;
          };

      s88Debug =
        if specialArgs ? s88Debug && builtins.isAttrs specialArgs.s88Debug then
          sanitizeDebug specialArgs.s88Debug
        else
          { };
    in
    {
      autoStart = container.autoStart or false;
      privateNetwork = container.privateNetwork or false;
      extraVeths = container.extraVeths or { };
      bindMounts = container.bindMounts or { };
      allowedDevices = container.allowedDevices or [ ];
      additionalCapabilities = container.additionalCapabilities or [ ];
      inherit firewall;
      specialArgs = {
        unitName = if specialArgs ? unitName then specialArgs.unitName else containerName;
        deploymentHostName =
          if specialArgs ? deploymentHostName then specialArgs.deploymentHostName else null;
        s88RoleName = if specialArgs ? s88RoleName then specialArgs.s88RoleName else null;
        s88Debug = s88Debug;
      };
    };

  sanitizedContainers = builtins.listToAttrs (
    map (containerName: {
      name = containerName;
      value = sanitizeContainer containerName renderedHostNetwork.containers.${containerName};
    }) (sortedAttrNames (renderedHostNetwork.containers or { }))
  );
in
{
  inherit
    system
    hostName
    hostContext
    intent
    globalInventory
    compilerOut
    forwardingOut
    controlPlaneOut
    ;

  intentPath = builtins.toString intentPath;
  inventoryPath = builtins.toString inventoryPath;

  renderedHost = {
    hostName = renderedHostNetwork.hostName or null;
    deploymentHostName = renderedHostNetwork.deploymentHostName or null;
    runtimeRole = renderedHostNetwork.runtimeRole or null;
    selectedUnits = renderedHostNetwork.selectedUnits or [ ];
    selectedRoleNames = renderedHostNetwork.selectedRoleNames or [ ];
    bridgeNameMap = renderedHostNetwork.bridgeNameMap or { };
    bridges = renderedHostNetwork.bridges or { };
    netdevs = renderedHostNetwork.netdevs or { };
    networks = renderedHostNetwork.networks or { };
    attachTargets = renderedHostNetwork.attachTargets or [ ];
    localAttachTargets = renderedHostNetwork.localAttachTargets or [ ];
    uplinks = renderedHostNetwork.uplinks or { };
    transitBridges = renderedHostNetwork.transitBridges or { };
    containers = sanitizedContainers;
    debug = renderedHostNetwork.debug or { };
  };
}
