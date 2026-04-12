{
  lib,
  mapKeaRuntimeTargetServiceModel,
  mapRadvdRuntimeTargetServiceModel,
}:
{
  artifactContext,
}:
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

  dedupeByJson =
    values:
    builtins.foldl'
      (
        acc: value:
        let
          key = json value;
        in
        if builtins.hasAttr key acc.byKey then
          acc
        else
          {
            order = acc.order ++ [ key ];
            byKey = acc.byKey // {
              "${key}" = value;
            };
          }
      )
      {
        order = [ ];
        byKey = { };
      }
      values;

  uniqueValues =
    values:
    let
      deduped = dedupeByJson values;
    in
    map (key: deduped.byKey.${key}) deduped.order;

  normalizeAdvertisementEntries =
    {
      runtimeTargetName,
      advertisements,
      aliases,
      label,
    }:
    uniqueValues (
      lib.concatMap (
        alias:
        if !(builtins.hasAttr alias advertisements) || advertisements.${alias} == null then
          [ ]
        else if builtins.isAttrs advertisements.${alias} then
          [ advertisements.${alias} ]
        else if builtins.isList advertisements.${alias} then
          map (entry: ensureAttrs "runtime target '${runtimeTargetName}'.advertisements.${alias} entry" entry)
            (ensureList "runtime target '${runtimeTargetName}'.advertisements.${alias}" advertisements.${alias})
        else
          throw "network-renderer-nixos: expected runtime target '${runtimeTargetName}'.advertisements.${alias} to be an attribute set, list, or null"
      ) aliases
    );

  filterEnabledEntries =
    runtimeTargetName: label: entries:
    lib.filter (
      entry:
      if entry ? enabled then
        ensureBool "runtime target '${runtimeTargetName}' ${label} advertisement.enabled" entry.enabled
      else
        true
    ) entries;

  context = ensureAttrs "artifactContext" artifactContext;

  runtimeTargetName = ensureString "artifactContext.runtimeTargetName" context.runtimeTargetName;

  runtimeTarget =
    if context ? runtimeTarget then
      ensureAttrs "artifactContext.runtimeTarget" context.runtimeTarget
    else
      throw "network-renderer-nixos: artifactContext is missing runtimeTarget";

  containerName =
    if !(context ? containerName) || context.containerName == null then
      null
    else
      ensureString "artifactContext.containerName" context.containerName;

  declaredContainers =
    if runtimeTarget ? containers then
      map (name: ensureString "runtime target '${runtimeTargetName}' container entry" name) (
        ensureList "runtime target '${runtimeTargetName}'.containers" runtimeTarget.containers
      )
    else
      [ ];

  advertisements =
    if runtimeTarget ? advertisements then
      ensureAttrs "runtime target '${runtimeTargetName}'.advertisements" runtimeTarget.advertisements
    else
      { };

  keaAdvertisements = filterEnabledEntries runtimeTargetName "Kea" (normalizeAdvertisementEntries {
    inherit
      runtimeTargetName
      advertisements
      ;
    aliases = [
      "dhcp4"
      "kea"
    ];
    label = "Kea";
  });

  radvdAdvertisements =
    filterEnabledEntries runtimeTargetName "radvd"
      (normalizeAdvertisementEntries {
        inherit
          runtimeTargetName
          advertisements
          ;
        aliases = [
          "ipv6Ra"
          "radvd"
          "ra"
        ];
        label = "radvd";
      });

  hasContainerServices = keaAdvertisements != [ ] || radvdAdvertisements != [ ];

  _requireContainerPlacement =
    if !hasContainerServices then
      true
    else if containerName == null then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' carries container services but is not placed in a container artifact context"
    else if builtins.length declaredContainers != 1 then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' carries container services but does not resolve to exactly one container"
    else if builtins.head declaredContainers != containerName then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' container service context does not match declared container '${builtins.head declaredContainers}'"
    else
      true;
in
builtins.seq _requireContainerPlacement {
  kea =
    if keaAdvertisements == [ ] then
      null
    else
      mapKeaRuntimeTargetServiceModel {
        inherit
          artifactContext
          ;
        advertisements = keaAdvertisements;
      };

  radvd =
    if radvdAdvertisements == [ ] then
      null
    else
      mapRadvdRuntimeTargetServiceModel {
        inherit
          artifactContext
          ;
        advertisements = radvdAdvertisements;
      };
}
