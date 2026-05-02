{
  lib,
  currentSite,
  communicationContract,
  tenantInterfaceByName,
  serviceInterfacesByName,
  upstreamInterfaceNames,
  upstreamInterfacesForUplink,
  wanEndpointNames,
  explicitWanNames,
  common,
}:

let
  inherit (common) sortedStrings asStringList fieldOr;

  canonicalInterfaceTags =
    if
      currentSite ? policy
      && builtins.isAttrs currentSite.policy
      && currentSite.policy ? interfaceTags
      && builtins.isAttrs currentSite.policy.interfaceTags
    then
      currentSite.policy.interfaceTags
    else
      { };

  fallbackInterfaceTags =
    if communicationContract ? interfaceTags && builtins.isAttrs communicationContract.interfaceTags then
      communicationContract.interfaceTags
    else
      { };

  interfaceTags = if canonicalInterfaceTags != { } then canonicalInterfaceTags else fallbackInterfaceTags;

  normalizeToken =
    token:
    if builtins.hasAttr token interfaceTags && builtins.isString interfaceTags.${token} then
      interfaceTags.${token}
    else
      token;

  allKnownInterfaces = sortedStrings (
    (builtins.attrValues tenantInterfaceByName) ++ upstreamInterfaceNames
  );

  resolveStringEndpoint =
    endpoint:
    let
      token = normalizeToken endpoint;
      uplinkMatches = upstreamInterfacesForUplink token;
    in
    if token == "any" then
      allKnownInterfaces
    else if token == "wan" || token == "external-wan" then
      wanEndpointNames
    else if token == "upstream" then
      upstreamInterfaceNames
    else if uplinkMatches != [ ] then
      uplinkMatches
    else if builtins.hasAttr token tenantInterfaceByName then
      [ tenantInterfaceByName.${token} ]
    else if builtins.hasAttr token serviceInterfacesByName then
      serviceInterfacesByName.${token}
    else
      [ ];

  resolveAttrEndpoint =
    endpoint:
    let
      kind = endpoint.kind or null;
    in
    if kind == "tenant" && endpoint ? name && builtins.hasAttr endpoint.name tenantInterfaceByName then
      [ tenantInterfaceByName.${endpoint.name} ]
    else if kind == "tenant-set" && endpoint ? members && builtins.isList endpoint.members then
      sortedStrings (
        lib.concatMap (
          member:
          if builtins.isString member && builtins.hasAttr member tenantInterfaceByName then
            [ tenantInterfaceByName.${member} ]
          else
            [ ]
        ) endpoint.members
      )
    else if
      kind == "external"
      && ((endpoint.name or null) == "wan" || (endpoint.name or null) == "external-wan")
    then
      wanEndpointNames
    else if kind == "external" && (endpoint.name or null) == "upstream" then
      upstreamInterfaceNames
    else if kind == "external" && endpoint ? uplinks && builtins.isList endpoint.uplinks then
      sortedStrings (
        lib.concatMap (
          uplinkName:
          let
            matches = resolveStringEndpoint uplinkName;
          in
          if matches != [ ] then matches else wanEndpointNames
        ) endpoint.uplinks
      )
    else if
      kind == "service" && endpoint ? name && builtins.hasAttr endpoint.name serviceInterfacesByName
    then
      serviceInterfacesByName.${endpoint.name}
    else
      let
        selectorValues = sortedStrings (
          lib.concatMap (field: asStringList (fieldOr endpoint field null)) [
            "selector"
            "selectors"
            "endpoint"
            "endpoints"
            "interface"
            "interfaces"
            "ifName"
            "ifNames"
            "name"
            "names"
          ]
        );
      in
      sortedStrings (lib.concatMap resolveStringEndpoint selectorValues);
in
rec {
  inherit interfaceTags allKnownInterfaces;

  resolveEndpoint =
    endpoint:
    if endpoint == null then
      [ ]
    else if endpoint == "any" then
      allKnownInterfaces
    else if builtins.isString endpoint then
      resolveStringEndpoint endpoint
    else if builtins.isList endpoint then
      sortedStrings (lib.concatMap resolveEndpoint endpoint)
    else if builtins.isAttrs endpoint then
      resolveAttrEndpoint endpoint
    else
      [ ];
}
