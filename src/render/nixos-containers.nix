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

  normalizeOptionalAddress =
    value:
    if value == null then
      null
    else if builtins.isString value && value != "" then
      value
    else
      null;

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
          rawInterface =
            if interface ? interface && builtins.isAttrs interface.interface then interface.interface else { };
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
          address4 = normalizeOptionalAddress (rawInterface.addr4 or null);
          address6 = normalizeOptionalAddress (rawInterface.addr6 or null);
        }
      ) bridgeInterfaceNames;

      _uniqueContainerHostVethNames = ensureUniqueNames "container '${containerName}' host veth names" (
        map (entry: entry.hostVethName) renderedInterfaceEntries
      );

      _uniqueContainerInterfaceNames = ensureUniqueNames "container '${containerName}' interface names" (
        map (entry: entry.containerInterfaceName) renderedInterfaceEntries
      );

      renderedExtraVeths = builtins.listToAttrs (
        map (entry: {
          name = entry.hostVethName;
          value = {
            hostBridge = entry.hostBridge;
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

      renameServiceScript = lib.concatStringsSep "\n" (
        map (
          entry:
          ''
            if ip link show dev "${entry.hostVethName}" >/dev/null 2>&1; then
              ip link set dev "${entry.hostVethName}" down || true
              ip link set dev "${entry.hostVethName}" name "${entry.containerInterfaceName}"
            fi
            ip link set dev "${entry.containerInterfaceName}" up
          ''
          + lib.optionalString (entry.address4 != null) ''
            ip addr replace ${entry.address4} dev "${entry.containerInterfaceName}"
          ''
          + lib.optionalString (entry.address6 != null) ''
            ip -6 addr replace ${entry.address6} dev "${entry.containerInterfaceName}"
          ''
        ) renderedInterfaceEntries
      );

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
      builtins.seq _uniqueContainerInterfaceNames (
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
            { pkgs, ... }:
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

              systemd.services.rename-container-interfaces = lib.mkIf (renderedInterfaceEntries != [ ]) {
                wantedBy = [ "network-pre.target" ];
                before = [
                  "network-pre.target"
                  "systemd-networkd.service"
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                path = [ pkgs.iproute2 ];
                script = renameServiceScript;
              };

              system.stateVersion =
                if container ? systemStateVersion && builtins.isString container.systemStateVersion then
                  container.systemStateVersion
                else
                  "24.11";
            };
        }
      )
    )
  ) containerModel.containers
)
