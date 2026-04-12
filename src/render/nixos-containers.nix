{ lib }:
containerModel:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  ensureUniqueNames =
    label: names:
    if builtins.length names == builtins.length (lib.unique names) then
      true
    else
      throw "network-renderer-nixos: duplicate ${label}: ${builtins.toJSON names}";

  mergeAttrsUnique =
    label: left: right:
    let
      duplicates = lib.filter (name: builtins.hasAttr name right) (sortedAttrNames left);
    in
    if duplicates == [ ] then
      left // right
    else
      throw "network-renderer-nixos: duplicate ${label}: ${builtins.toJSON duplicates}";

  hashFragment = value: builtins.substring 0 11 (builtins.hashString "sha256" value);

  hostVethNameFor =
    {
      deploymentHostName,
      containerName,
      nodeName,
      containerInterfaceName,
    }:
    "vh-${hashFragment "${deploymentHostName}:${containerName}:${nodeName}:${containerInterfaceName}"}";

  allContainerNames = sortedAttrNames containerModel.containers;

  allRenderedHostVethNames = lib.concatMap (
    containerName:
    let
      container = containerModel.containers.${containerName};

      interfaceNames =
        if container ? interfaces && builtins.isAttrs container.interfaces then
          sortedAttrNames container.interfaces
        else
          [ ];

      bridgeInterfaceNames = lib.filter (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
        in
        interface.hostBridge != null
      ) interfaceNames;
    in
    map (
      interfaceName:
      let
        interface = container.interfaces.${interfaceName};
      in
      hostVethNameFor {
        deploymentHostName =
          if container ? deploymentHostName && builtins.isString container.deploymentHostName then
            container.deploymentHostName
          else
            containerModel.renderHostName or "host";
        inherit containerName;
        nodeName =
          if container ? nodeName && builtins.isString container.nodeName then
            container.nodeName
          else
            containerName;
        containerInterfaceName = interface.containerInterfaceName;
      }
    ) bridgeInterfaceNames
  ) allContainerNames;

  _uniqueRenderedHostVethNames = ensureUniqueNames "rendered container host veth names" allRenderedHostVethNames;
in
builtins.seq _uniqueRenderedHostVethNames (
  builtins.mapAttrs (
    containerName: container:
    let
      interfaceNames =
        if container ? interfaces && builtins.isAttrs container.interfaces then
          sortedAttrNames container.interfaces
        else
          [ ];

      bridgeInterfaceNames = lib.filter (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
        in
        interface.hostBridge != null
      ) interfaceNames;

      renderedInterfaceEntries = map (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
          hostVethName = hostVethNameFor {
            deploymentHostName =
              if container ? deploymentHostName && builtins.isString container.deploymentHostName then
                container.deploymentHostName
              else
                containerModel.renderHostName or "host";
            inherit containerName;
            nodeName =
              if container ? nodeName && builtins.isString container.nodeName then
                container.nodeName
              else
                containerName;
            containerInterfaceName = interface.containerInterfaceName;
          };
        in
        {
          hostVethName = hostVethName;
          containerInterfaceName = interface.containerInterfaceName;
          hostBridge = interface.hostBridge;
        }
      ) bridgeInterfaceNames;

      _uniqueContainerHostVethNames = ensureUniqueNames "container '${containerName}' host veth names" (
        map (entry: entry.hostVethName) renderedInterfaceEntries
      );

      renderedExtraVeths = builtins.listToAttrs (
        map (entry: {
          name = entry.hostVethName;
          value = {
            hostBridge = entry.hostBridge;
          };
        }) renderedInterfaceEntries
      );

      renderedInterfaceLinks = builtins.listToAttrs (
        map (entry: {
          name = "10-${entry.hostVethName}";
          value = {
            matchConfig.OriginalName = entry.hostVethName;
            linkConfig.Name = entry.containerInterfaceName;
          };
        }) renderedInterfaceEntries
      );

      passthroughExtraVeths =
        if container ? extraVeths && builtins.isAttrs container.extraVeths then
          container.extraVeths
        else
          { };

      mergedExtraVeths =
        mergeAttrsUnique "container '${containerName}' extraVeths" passthroughExtraVeths
          renderedExtraVeths;

      containerTemplateImports =
        if container ? containerTemplate && container.containerTemplate != null then
          if builtins.isList container.containerTemplate then
            container.containerTemplate
          else
            [ container.containerTemplate ]
        else
          [ ];

      containerConfigImports =
        if container ? config && container.config != null then
          if builtins.isList container.config then container.config else [ container.config ]
        else
          [ ];

      containerImports = containerTemplateImports ++ containerConfigImports;

      passthrough = builtins.removeAttrs container [
        "containerName"
        "nodeName"
        "logicalName"
        "deploymentHostName"
        "interfaces"
        "containerTemplate"
        "systemStateVersion"
        "config"
        "extraVeths"
        "runtimeRole"
      ];
    in
    builtins.seq _uniqueContainerHostVethNames (
      passthrough
      // {
        autoStart =
          if container ? autoStart && builtins.isBool container.autoStart then container.autoStart else false;

        privateNetwork =
          if container ? privateNetwork && builtins.isBool container.privateNetwork then
            container.privateNetwork
          else
            true;

        extraVeths = mergedExtraVeths;

        config =
          { ... }:
          {
            imports = containerImports;

            networking.hostName =
              if container ? logicalName && builtins.isString container.logicalName then
                container.logicalName
              else
                containerName;

            networking.useNetworkd = true;
            networking.useHostResolvConf = false;
            services.resolved.enable = false;

            systemd.network.enable = true;
            systemd.network.links = renderedInterfaceLinks;

            system.stateVersion =
              if container ? systemStateVersion && builtins.isString container.systemStateVersion then
                container.systemStateVersion
              else
                "24.11";
          };
      }
    )
  ) containerModel.containers
)
