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

  traceUpstreamContainerMismatch =
    runtimeTargetName: containerName: declaredContainer:
    builtins.trace ''
      WARNING: network-renderer-nixos tolerated a runtime target/container service mismatch for '${runtimeTargetName}'.
      artifactContext.containerName='${containerName}'
      declared container='${declaredContainer}'
      This should be patched upstream at the control-plane/inventory layer rather than relying on renderer fallback.
    '' true;

  normalizeDeclaredContainerName =
    runtimeTargetName: index: value:
    if builtins.isString value then
      ensureString "runtime target '${runtimeTargetName}' container entry" value
    else
      let
        container = ensureAttrs "runtime target '${runtimeTargetName}' container entry" value;
      in
      if container ? runtimeName then
        ensureString "runtime target '${runtimeTargetName}' container entry.runtimeName" container.runtimeName
      else if container ? container then
        ensureString "runtime target '${runtimeTargetName}' container entry.container" container.container
      else if container ? name then
        ensureString "runtime target '${runtimeTargetName}' container entry.name" container.name
      else if container ? logicalName then
        ensureString "runtime target '${runtimeTargetName}' container entry.logicalName" container.logicalName
      else
        throw "network-renderer-nixos: runtime target '${runtimeTargetName}' container entry ${toString index} must define runtimeName, container, name, or logicalName";

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
      let
        containerEntries = ensureList "runtime target '${runtimeTargetName}'.containers" runtimeTarget.containers;
      in
      map (
        index:
        normalizeDeclaredContainerName runtimeTargetName index (builtins.elemAt containerEntries index)
      ) (lib.range 0 ((builtins.length containerEntries) - 1))
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

  declaredContainerName =
    if builtins.length declaredContainers == 1 then builtins.head declaredContainers else null;

  allowContainerContextMismatch =
    hasContainerServices
    && containerName != null
    && declaredContainerName != null
    && containerName != declaredContainerName
    && declaredContainerName == "default";

  _requireContainerPlacement =
    if !hasContainerServices then
      true
    else if containerName == null then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' carries container services but is not placed in a container artifact context"
    else if builtins.length declaredContainers != 1 then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' carries container services but does not resolve to exactly one container"
    else if builtins.head declaredContainers == containerName then
      true
    else if allowContainerContextMismatch then
      traceUpstreamContainerMismatch runtimeTargetName containerName declaredContainerName
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' container service context does not match declared container '${builtins.head declaredContainers}'";
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
