{
  lib,
  metadataSourcePaths,
  debugEnabled ? false,
  runtimeContext,
  normalizedRuntimeTargets,
  hostRenderings,
  deploymentHostNames,
  controlPlane,
  resolvedInventory,
}:

let
  isa = import ../alarm/isa18.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  unitNames = sortedAttrNames normalizedRuntimeTargets;

  pipelineAlarmModel = isa.normalizeModel controlPlane;

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

      s88Warnings =
        if specialArgs ? s88Warnings && builtins.isList specialArgs.s88Warnings then
          lib.filter builtins.isString specialArgs.s88Warnings
        else
          [ ];

      s88Alarms =
        if specialArgs ? s88Alarms && builtins.isList specialArgs.s88Alarms then
          specialArgs.s88Alarms
        else
          [ ];
    in
    {
      autoStart = container.autoStart or false;
      privateNetwork = container.privateNetwork or false;
      extraVeths = container.extraVeths or { };
      bindMounts = container.bindMounts or { };
      allowedDevices = container.allowedDevices or [ ];
      additionalCapabilities = container.additionalCapabilities or [ ];
      inherit firewall;
      warnings = s88Warnings;
      alarms = s88Alarms;
      specialArgs = {
        unitName = if specialArgs ? unitName then specialArgs.unitName else containerName;
        deploymentHostName =
          if specialArgs ? deploymentHostName then specialArgs.deploymentHostName else null;
        s88RoleName = if specialArgs ? s88RoleName then specialArgs.s88RoleName else null;
        s88Debug = s88Debug;
      };
    };

  sanitizedContainersForHost =
    hostRendering:
    builtins.listToAttrs (
      map (containerName: {
        name = containerName;
        value = sanitizeContainer containerName hostRendering.containers.${containerName};
      }) (sortedAttrNames (hostRendering.containers or { }))
    );

  hostRenderingsDebug = builtins.mapAttrs (_hostName: hostRendering: {
    hostName = hostRendering.hostName or null;
    deploymentHostName = hostRendering.deploymentHostName or null;
    runtimeRole = hostRendering.runtimeRole or null;
    selectedUnits = hostRendering.selectedUnits or [ ];
    selectedRoleNames = hostRendering.selectedRoleNames or [ ];
    bridgeNameMap = hostRendering.bridgeNameMap or { };
    bridges = hostRendering.bridges or { };
    netdevs = hostRendering.netdevs or { };
    networks = hostRendering.networks or { };
    attachTargets = hostRendering.attachTargets or [ ];
    localAttachTargets = hostRendering.localAttachTargets or [ ];
    uplinks = hostRendering.uplinks or { };
    transitBridges = hostRendering.transitBridges or { };
    containers = sanitizedContainersForHost hostRendering;
    debug = hostRendering.debug or { };
  }) hostRenderings;

  attachTargetForUnitInterface =
    {
      hostRendering,
      unitName,
      ifName,
      iface,
    }:
    let
      matches = lib.filter (
        target:
        (target.unitName or null) == unitName
        && (
          (target.ifName or null) == ifName
          || ((target.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.interface.renderedIfName or null) == (iface.renderedIfName or null))
          || ((target.hostBridgeName or null) == (iface.hostBridge or null))
        )
      ) (hostRendering.attachTargets or [ ]);
    in
    if builtins.length matches == 1 then builtins.head matches else null;

  renderedInterfacesForUnit =
    unitName:
    let
      deploymentHostName = runtimeContext.deploymentHostForUnit {
        cpm = controlPlane;
        inventory = resolvedInventory;
        inherit unitName;
        file = "s88/CM/network/render/dry-config-model.nix";
      };

      hostRendering =
        if builtins.hasAttr deploymentHostName hostRenderings then
          hostRenderings.${deploymentHostName}
        else
          throw ''
            s88/CM/network/render/dry-config-model.nix: unit '${unitName}' references unknown deployment host '${deploymentHostName}'
          '';

      bridgeNameMap = hostRendering.bridgeNameMap or { };
      interfaces = normalizedRuntimeTargets.${unitName}.interfaces or { };

      globalBridgeNameMap = lib.foldl' (
        acc: hostName: acc // (hostRenderings.${hostName}.bridgeNameMap or { })
      ) { } deploymentHostNames;
    in
    builtins.listToAttrs (
      map (
        ifName:
        let
          iface = interfaces.${ifName};

          attachTarget = attachTargetForUnitInterface {
            inherit
              hostRendering
              unitName
              ifName
              iface
              ;
          };

          renderedHostBridgeName =
            if
              attachTarget != null
              && attachTarget ? renderedHostBridgeName
              && builtins.isString attachTarget.renderedHostBridgeName
            then
              attachTarget.renderedHostBridgeName
            else if builtins.hasAttr iface.hostBridge bridgeNameMap then
              bridgeNameMap.${iface.hostBridge}
            else if builtins.hasAttr iface.hostBridge globalBridgeNameMap then
              globalBridgeNameMap.${iface.hostBridge}
            else
              throw ''
                s88/CM/network/render/dry-config-model.nix: missing rendered bridge for '${iface.hostBridge}' (unit '${unitName}', interface '${ifName}')

                deploymentHostName: ${deploymentHostName}

                local bridgeNameMap keys:
                ${builtins.toJSON (sortedAttrNames bridgeNameMap)}

                global bridgeNameMap keys:
                ${builtins.toJSON (sortedAttrNames globalBridgeNameMap)}
              '';
        in
        {
          name = ifName;
          value = iface // {
            inherit renderedHostBridgeName;
          };
        }
      ) (sortedAttrNames interfaces)
    );

  renderHosts = builtins.listToAttrs (
    map (
      hostName:
      let
        hostRendering = hostRenderings.${hostName};
      in
      {
        name = hostName;
        value = {
          network = {
            bridges = hostRendering.bridges;
            netdevs = hostRendering.netdevs;
            networks = hostRendering.networks;
          };
        };
      }
    ) deploymentHostNames
  );

  renderNodes = builtins.listToAttrs (
    map (unitName: {
      name = unitName;
      value = {
        logicalNode = runtimeContext.logicalNodeForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "s88/CM/network/render/dry-config-model.nix";
        };

        deploymentHostName = runtimeContext.deploymentHostForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "s88/CM/network/render/dry-config-model.nix";
        };

        role = runtimeContext.roleForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "s88/CM/network/render/dry-config-model.nix";
        };

        interfaces = renderedInterfacesForUnit unitName;
        loopback = normalizedRuntimeTargets.${unitName}.loopback or { };
      };
    }) unitNames
  );

  renderContainers = builtins.listToAttrs (
    map (hostName: {
      name = hostName;
      value = sanitizedContainersForHost hostRenderings.${hostName};
    }) deploymentHostNames
  );

  output = {
    metadata = {
      sourcePaths = metadataSourcePaths;
      warnings = pipelineAlarmModel.warningMessages;
      alarms = pipelineAlarmModel.alarms;
    };

    render = {
      hosts = renderHosts;
      nodes = renderNodes;
      containers = renderContainers;
    };
  }
  // lib.optionalAttrs debugEnabled {
    debug = {
      controlPlane = controlPlane;
      inventory = resolvedInventory;
      normalizedRuntimeTargets = normalizedRuntimeTargets;
      hostRenderings = hostRenderingsDebug;
    };
  };
in
output
