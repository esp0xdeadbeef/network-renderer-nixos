{ lib }:
let
  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureBool =
    name: value:
    if builtins.isBool value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a boolean";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  json = value: builtins.toJSON value;

  normalizeServiceCandidateValue =
    name: value:
    if builtins.isAttrs value then
      value
    else if builtins.isBool value then
      { enable = value; }
    else if builtins.isString value || builtins.isList value || builtins.isInt value then
      {
        enable = true;
        raw = value;
      }
    else
      throw "network-renderer-nixos: unsupported ${name} type '${builtins.typeOf value}'";

  mergeUnique =
    label: left: right:
    if builtins.isAttrs left && builtins.isAttrs right then
      let
        leftNames = builtins.attrNames left;
        rightNames = builtins.attrNames right;
        allNames = lib.unique (leftNames ++ rightNames);
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
          else
            {
              inherit name;
              value = mergeUnique "${label}.${name}" left.${name} right.${name};
            }
        ) allNames
      )
    else if json left == json right then
      left
    else
      throw "network-renderer-nixos: conflicting ${label} values";

  collectExplicitServiceCandidates =
    {
      label,
      aliases,
      interfaceKey,
      interface,
    }:
    let
      interfaceDef = ensureAttrs "runtime target interface '${interfaceKey}'" interface;

      serviceAdvertisements =
        if interfaceDef ? serviceAdvertisements then
          ensureAttrs "runtime target interface '${interfaceKey}'.serviceAdvertisements" interfaceDef.serviceAdvertisements
        else
          { };

      rawCandidates =
        (map (alias: {
          source = "runtime target interface '${interfaceKey}'.serviceAdvertisements.${alias}";
          value =
            if builtins.hasAttr alias serviceAdvertisements then serviceAdvertisements.${alias} else null;
        }) aliases)
        ++ (map (alias: {
          source = "runtime target interface '${interfaceKey}'.${alias}";
          value = if builtins.hasAttr alias interfaceDef then interfaceDef.${alias} else null;
        }) aliases);

      presentCandidates = lib.filter (candidate: candidate.value != null) rawCandidates;

      normalizedCandidates = map (
        candidate: normalizeServiceCandidateValue candidate.source candidate.value
      ) presentCandidates;
    in
    if normalizedCandidates == [ ] then
      null
    else
      builtins.foldl' (
        acc: candidate:
        mergeUnique "${label} service config for runtime target interface '${interfaceKey}'" acc candidate
      ) { } normalizedCandidates;

  selectExplicitServiceConfig =
    {
      label,
      aliases,
      interfaceKey,
      interface,
    }:
    let
      serviceConfig = collectExplicitServiceCandidates {
        inherit
          label
          aliases
          interfaceKey
          interface
          ;
      };
    in
    if serviceConfig == null then
      null
    else
      let
        enabled =
          if serviceConfig ? enable then
            ensureBool "explicit ${label} enablement for runtime target interface '${interfaceKey}'" serviceConfig.enable
          else
            true;
      in
      if enabled then serviceConfig else null;

  resolveRuntimeInterfaceName =
    {
      label,
      runtimeTargetName,
      interfaceKey,
      interface,
      serviceConfig,
    }:
    let
      interfaceDef = ensureAttrs "runtime target '${runtimeTargetName}' interface '${interfaceKey}'" interface;
      config =
        if serviceConfig == null then
          { }
        else
          ensureAttrs "explicit ${label} service configuration for runtime target '${runtimeTargetName}' interface '${interfaceKey}'" serviceConfig;
    in
    if config ? interfaceName then
      ensureString "explicit ${label} service interfaceName for runtime target '${runtimeTargetName}' interface '${interfaceKey}'" config.interfaceName
    else if config ? bindInterface then
      ensureString "explicit ${label} service bindInterface for runtime target '${runtimeTargetName}' interface '${interfaceKey}'" config.bindInterface
    else if
      interfaceDef ? runtimeIfName
      && builtins.isString interfaceDef.runtimeIfName
      && interfaceDef.runtimeIfName != ""
    then
      interfaceDef.runtimeIfName
    else if
      interfaceDef ? renderedIfName
      && builtins.isString interfaceDef.renderedIfName
      && interfaceDef.renderedIfName != ""
    then
      interfaceDef.renderedIfName
    else if
      interfaceDef ? containerInterfaceName
      && builtins.isString interfaceDef.containerInterfaceName
      && interfaceDef.containerInterfaceName != ""
    then
      interfaceDef.containerInterfaceName
    else
      throw "network-renderer-nixos: explicit ${label} service on runtime target '${runtimeTargetName}' interface '${interfaceKey}' requires interfaceName/bindInterface or runtimeIfName/renderedIfName/containerInterfaceName";
in
{
  inherit
    selectExplicitServiceConfig
    resolveRuntimeInterfaceName
    ;
}
