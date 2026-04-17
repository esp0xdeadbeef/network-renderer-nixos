{ lib, mapContainerRuntimeArtifactModel }:
{
  normalizedModel,
  deploymentHostName,
  defaults ? { },
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureList =
    name: value:
    if builtins.isList value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a list";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  json = value: builtins.toJSON value;

  mergeAttrsUnique =
    label: left: right:
    let
      names = lib.unique (sortedAttrNames left ++ sortedAttrNames right);
    in
    builtins.listToAttrs (
      map (
        name:
        if !(builtins.hasAttr name left) then
          {
            inherit name;
            value = right.${name};
          }
        else if !(builtins.hasAttr name right) then
          {
            inherit name;
            value = left.${name};
          }
        else if json left.${name} == json right.${name} then
          {
            inherit name;
            value = left.${name};
          }
        else
          throw "network-renderer-nixos: conflicting ${label} for '${name}'"
      ) names
    );

  siteData = ensureAttrs "control_plane_model.data" normalizedModel.siteData;

  runtimeTargetsForSite =
    enterpriseName: siteName: site:
    if site ? runtimeTargets then
      ensureAttrs "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets" site.runtimeTargets
    else
      { };

  containerNamesForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    if runtimeTarget ? containers then
      map
        (
          containerName:
          ensureString "container name for runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" containerName
        )
        (
          ensureList "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets.${runtimeTargetName}.containers" runtimeTarget.containers
        )
    else
      [ ];

  runtimeInterfacesForTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    if
      runtimeTarget ? effectiveRuntimeRealization
      && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization
      && runtimeTarget.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization.interfaces
    then
      runtimeTarget.effectiveRuntimeRealization.interfaces
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing effectiveRuntimeRealization.interfaces";

  runtimeIfNameForInterface =
    enterpriseName: siteName: runtimeTargetName: interfaceName: interface:
    if
      interface ? runtimeIfName
      && builtins.isString interface.runtimeIfName
      && interface.runtimeIfName != ""
    then
      interface.runtimeIfName
    else if
      interface ? renderedIfName
      && builtins.isString interface.renderedIfName
      && interface.renderedIfName != ""
    then
      interface.renderedIfName
    else if
      interface ? containerInterfaceName
      && builtins.isString interface.containerInterfaceName
      && interface.containerInterfaceName != ""
    then
      interface.containerInterfaceName
    else
      throw "network-renderer-nixos: interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing runtimeIfName/renderedIfName/containerInterfaceName";

  hashFragment = value: builtins.substring 0 11 (builtins.hashString "sha256" value);

  directBridgeNameForInterface =
    interface:
    let
      backingRef =
        if interface ? backingRef && builtins.isAttrs interface.backingRef then
          interface.backingRef
        else
          null;

      linkIdentity =
        if
          backingRef != null && backingRef ? id && builtins.isString backingRef.id && backingRef.id != ""
        then
          backingRef.id
        else if
          backingRef != null
          && backingRef ? name
          && builtins.isString backingRef.name
          && backingRef.name != ""
        then
          backingRef.name
        else if
          interface ? sourceInterface
          && builtins.isString interface.sourceInterface
          && interface.sourceInterface != ""
        then
          interface.sourceInterface
        else
          null;
    in
    if linkIdentity == null then null else "bp-${hashFragment linkIdentity}";

  simulatedBridgeNameForP2pInterface =
    interface:
    let
      backingRef =
        if interface ? backingRef && builtins.isAttrs interface.backingRef then
          interface.backingRef
        else
          null;

      linkIdentity =
        if
          backingRef != null && backingRef ? id && builtins.isString backingRef.id && backingRef.id != ""
        then
          backingRef.id
        else if
          backingRef != null
          && backingRef ? name
          && builtins.isString backingRef.name
          && backingRef.name != ""
        then
          backingRef.name
        else if
          interface ? sourceInterface
          && builtins.isString interface.sourceInterface
          && interface.sourceInterface != ""
        then
          interface.sourceInterface
        else
          null;
    in
    if linkIdentity == null then
      throw "network-renderer-nixos: simulated p2p interface requires backingRef.id/backingRef.name/sourceInterface"
    else
      "bp-${hashFragment linkIdentity}";

  hostBridgeForInterface =
    interface:
    if
      interface ? sourceKind && builtins.isString interface.sourceKind && interface.sourceKind == "p2p"
    then
      simulatedBridgeNameForP2pInterface interface
    else if
      interface ? hostUplink
      && builtins.isAttrs interface.hostUplink
      && interface.hostUplink ? bridge
      && builtins.isString interface.hostUplink.bridge
      && interface.hostUplink.bridge != ""
    then
      interface.hostUplink.bridge
    else if
      interface ? attach
      && builtins.isAttrs interface.attach
      && interface.attach ? bridge
      && builtins.isString interface.attach.bridge
      && interface.attach.bridge != ""
    then
      interface.attach.bridge
    else if
      interface ? sourceKind && builtins.isString interface.sourceKind && interface.sourceKind == "direct"
    then
      directBridgeNameForInterface interface
    else
      null;

  logicalContainerNameForRuntimeTarget =
    runtimeTargetName: runtimeTarget:
    if
      runtimeTarget ? logicalNode
      && builtins.isAttrs runtimeTarget.logicalNode
      && runtimeTarget.logicalNode ? name
      && builtins.isString runtimeTarget.logicalNode.name
      && runtimeTarget.logicalNode.name != ""
    then
      runtimeTarget.logicalNode.name
    else
      runtimeTargetName;

  runtimeRoleForRuntimeTarget =
    runtimeTarget:
    if
      runtimeTarget ? logicalNode
      && builtins.isAttrs runtimeTarget.logicalNode
      && runtimeTarget.logicalNode ? role
      && builtins.isString runtimeTarget.logicalNode.role
      && runtimeTarget.logicalNode.role != ""
    then
      runtimeTarget.logicalNode.role
    else if
      runtimeTarget ? role && builtins.isString runtimeTarget.role && runtimeTarget.role != ""
    then
      runtimeTarget.role
    else
      null;

  interfaceModelForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: interfaceName: interface:
    let
      interfaceDef = ensureAttrs "runtime target '${runtimeTargetName}' interface '${interfaceName}' in '${enterpriseName}.${siteName}'" interface;
    in
    {
      hostBridge = hostBridgeForInterface interfaceDef;
      containerInterfaceName =
        runtimeIfNameForInterface enterpriseName siteName runtimeTargetName interfaceName
          interfaceDef;
      interface = interfaceDef;
    };

  interfaceModelsForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    let
      interfaces = runtimeInterfacesForTarget enterpriseName siteName runtimeTargetName runtimeTarget;
    in
    builtins.foldl' (
      acc: interfaceName:
      let
        interface = interfaces.${interfaceName};
        resolvedInterfaceName =
          runtimeIfNameForInterface enterpriseName siteName runtimeTargetName interfaceName
            interface;
      in
      mergeAttrsUnique "simulated runtime target '${runtimeTargetName}' interfaces" acc {
        "${resolvedInterfaceName}" =
          interfaceModelForRuntimeTarget enterpriseName siteName runtimeTargetName interfaceName
            interface;
      }
    ) { } (sortedAttrNames interfaces);

  resolvedDefaults = if builtins.isAttrs defaults then defaults else { };

  containerEntries = lib.concatMap (
    enterpriseName:
    let
      enterpriseSites =
        ensureAttrs "control_plane_model.data.${enterpriseName}"
          siteData.${enterpriseName};
    in
    lib.concatMap (
      siteName:
      let
        site =
          ensureAttrs "control_plane_model.data.${enterpriseName}.${siteName}"
            enterpriseSites.${siteName};
        runtimeTargets = runtimeTargetsForSite enterpriseName siteName site;
      in
      lib.concatMap (
        runtimeTargetName:
        let
          runtimeTarget = runtimeTargets.${runtimeTargetName};
          declaredContainers =
            containerNamesForRuntimeTarget enterpriseName siteName runtimeTargetName
              runtimeTarget;

          _requireSinglePlacement =
            if declaredContainers == [ ] then
              true
            else if builtins.length declaredContainers == 1 then
              true
            else
              throw "network-renderer-nixos: vm simulated container model requires runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' to resolve to exactly one container placement";

          containerName = logicalContainerNameForRuntimeTarget runtimeTargetName runtimeTarget;
          runtimeRole = runtimeRoleForRuntimeTarget runtimeTarget;

          artifactModel = mapContainerRuntimeArtifactModel {
            inherit
              normalizedModel
              enterpriseName
              siteName
              runtimeTargetName
              runtimeTarget
              ;
            hostName = deploymentHostName;
            inherit containerName;
          };
        in
        if declaredContainers == [ ] then
          [ ]
        else
          builtins.seq _requireSinglePlacement [
            {
              name = containerName;
              value = lib.recursiveUpdate resolvedDefaults {
                inherit
                  containerName
                  deploymentHostName
                  runtimeRole
                  ;
                nodeName = containerName;
                logicalName = containerName;
                interfaces =
                  interfaceModelsForRuntimeTarget enterpriseName siteName runtimeTargetName
                    runtimeTarget;
                artifactFiles = artifactModel.files;
                nftablesArtifactPath = artifactModel.nftablesArtifactPath;
              };
            }
          ]
      ) (sortedAttrNames runtimeTargets)
    ) (sortedAttrNames enterpriseSites)
  ) (sortedAttrNames siteData);

  containerNames = map (entry: entry.name) containerEntries;

  _validateUniqueContainerNames =
    if builtins.length containerNames == builtins.length (lib.unique containerNames) then
      true
    else
      throw "network-renderer-nixos: vm simulated container model resolved duplicate runtime target container names";
in
builtins.seq _validateUniqueContainerNames {
  renderHostName = deploymentHostName;
  containers = builtins.listToAttrs containerEntries;
  debug = {
    deploymentHostName = deploymentHostName;
    containerNames = containerNames;
  };
}
