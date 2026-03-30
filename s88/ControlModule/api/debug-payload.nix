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

  sanitizeContainer = containerName: container: {
    autoStart = container.autoStart or false;
    privateNetwork = container.privateNetwork or false;
    extraVeths = container.extraVeths or { };
    bindMounts = container.bindMounts or { };
    allowedDevices = container.allowedDevices or [ ];
    additionalCapabilities = container.additionalCapabilities or [ ];
    firewall =
      if
        container ? specialArgs
        && builtins.isAttrs container.specialArgs
        && container.specialArgs ? s88Firewall
        && builtins.isAttrs container.specialArgs.s88Firewall
      then
        {
          enable = container.specialArgs.s88Firewall.enable or false;
          ruleset =
            if
              container.specialArgs.s88Firewall ? ruleset
              && builtins.isString container.specialArgs.s88Firewall.ruleset
            then
              container.specialArgs.s88Firewall.ruleset
            else
              "";
        }
      else
        {
          enable = false;
          ruleset = "";
        };
    specialArgs = {
      unitName =
        if container ? specialArgs && container.specialArgs ? unitName then
          container.specialArgs.unitName
        else
          containerName;
      deploymentHostName =
        if container ? specialArgs && container.specialArgs ? deploymentHostName then
          container.specialArgs.deploymentHostName
        else
          null;
      s88RoleName =
        if container ? specialArgs && container.specialArgs ? s88RoleName then
          container.specialArgs.s88RoleName
        else
          null;
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
