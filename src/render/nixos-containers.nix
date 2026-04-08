{ lib }:
containerModel:
builtins.mapAttrs (
  containerName: container:
  let
    interfaceNames = lib.sort builtins.lessThan (builtins.attrNames container.interfaces);

    bridgeInterfaceNames = lib.filter (
      interfaceName:
      let
        interface = container.interfaces.${interfaceName};
      in
      interface.hostBridge != null
    ) interfaceNames;

    renderedExtraVeths = builtins.listToAttrs (
      map (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
        in
        {
          name = interface.containerInterfaceName;
          value = {
            hostBridge = interface.hostBridge;
          };
        }
      ) bridgeInterfaceNames
    );

    passthroughExtraVeths =
      if container ? extraVeths && builtins.isAttrs container.extraVeths then
        container.extraVeths
      else
        { };

    containerImports =
      if container ? containerTemplate && container.containerTemplate != null then
        if builtins.isList container.containerTemplate then
          container.containerTemplate
        else
          [ container.containerTemplate ]
      else
        [ ];

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
    ];
  in
  passthrough
  // {
    autoStart =
      if container ? autoStart && builtins.isBool container.autoStart then container.autoStart else false;

    privateNetwork =
      if container ? privateNetwork && builtins.isBool container.privateNetwork then
        container.privateNetwork
      else
        true;

    extraVeths = passthroughExtraVeths // renderedExtraVeths;

    config =
      { ... }:
      {
        imports = containerImports;
        networking.hostName =
          if container ? logicalName && builtins.isString container.logicalName then
            container.logicalName
          else
            containerName;
        system.stateVersion =
          if container ? systemStateVersion && builtins.isString container.systemStateVersion then
            container.systemStateVersion
          else
            "24.11";
      };
  }
) containerModel.containers
