{ lib }:
{ normalizedModel }:
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

  validPathSegment =
    name: value:
    let
      s = toString value;
    in
    if s == "" then
      throw "network-renderer-nixos: ${name} must not be empty"
    else if s == "." || s == ".." then
      throw "network-renderer-nixos: ${name} '${s}' is not a valid artifact path segment"
    else if lib.hasInfix "/" s then
      throw "network-renderer-nixos: ${name} '${s}' must not contain '/'"
    else
      s;

  siteData = ensureAttrs "control_plane_model.data" normalizedModel.siteData;

  _haveSiteData =
    if siteData == { } then
      throw "network-renderer-nixos: control-plane output is missing control_plane_model.data"
    else
      true;

  runtimeTargetsForSite =
    enterpriseName: siteName: site:
    if site ? runtimeTargets then
      ensureAttrs "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets" site.runtimeTargets
    else
      { };

  hostNameForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    if !(runtimeTarget ? placement) || !(builtins.isAttrs runtimeTarget.placement) then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing placement"
    else if
      !(runtimeTarget.placement ? host)
      || !(builtins.isString runtimeTarget.placement.host)
      || runtimeTarget.placement.host == ""
    then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing placement.host"
    else
      validPathSegment "host name for runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" runtimeTarget.placement.host;

  containerNamesForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    let
      containerNames =
        if runtimeTarget ? containers then
          map
            (
              containerName:
              validPathSegment "container name for runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" containerName
            )
            (
              ensureList "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets.${runtimeTargetName}.containers" runtimeTarget.containers
            )
        else
          [ ];

      uniqueContainerNames = lib.unique containerNames;

      _uniqueContainerNames =
        if builtins.length containerNames == builtins.length uniqueContainerNames then
          true
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' defines duplicate container names";
    in
    builtins.seq _uniqueContainerNames uniqueContainerNames;

  contextEntry = artifactPathPrefix: value: {
    name = artifactPathPrefix;
    value = value // {
      artifactPathPrefix = artifactPathPrefix;
    };
  };

  contextEntries = lib.concatMap (
    enterpriseName:
    let
      enterpriseSegment = validPathSegment "enterprise name" enterpriseName;
      enterpriseSites =
        ensureAttrs "control_plane_model.data.${enterpriseName}"
          siteData.${enterpriseName};
    in
    lib.concatMap (
      siteName:
      let
        siteSegment = validPathSegment "site name" siteName;
        site =
          ensureAttrs "control_plane_model.data.${enterpriseName}.${siteName}"
            enterpriseSites.${siteName};
        sitePath = "${enterpriseSegment}/${siteSegment}";
        runtimeTargets = runtimeTargetsForSite enterpriseName siteName site;
      in
      lib.concatMap (
        runtimeTargetName:
        let
          runtimeTarget = runtimeTargets.${runtimeTargetName};
          runtimeTargetSegment = validPathSegment "runtime target name" runtimeTargetName;
          hostName = hostNameForRuntimeTarget enterpriseName siteName runtimeTargetName runtimeTarget;
          containerNames =
            containerNamesForRuntimeTarget enterpriseName siteName runtimeTargetName
              runtimeTarget;
          hostPath = "${sitePath}/${hostName}";
        in
        if containerNames == [ ] then
          [
            (contextEntry "${hostPath}/runtime-targets/${runtimeTargetSegment}" {
              inherit
                enterpriseName
                siteName
                hostName
                runtimeTargetName
                runtimeTarget
                ;
              containerName = null;
              siteData = site;
            })
          ]
        else
          map (
            containerName:
            contextEntry "${hostPath}/containers/${containerName}/runtime-targets/${runtimeTargetSegment}" {
              inherit
                enterpriseName
                siteName
                hostName
                containerName
                runtimeTargetName
                runtimeTarget
                ;
              siteData = site;
            }
          ) containerNames
      ) (sortedAttrNames runtimeTargets)
    ) (sortedAttrNames enterpriseSites)
  ) (sortedAttrNames siteData);

  artifactPathPrefixes = map (entry: entry.name) contextEntries;

  _uniquePaths =
    if builtins.length artifactPathPrefixes == builtins.length (lib.unique artifactPathPrefixes) then
      true
    else
      throw "network-renderer-nixos: runtime target artifact contexts produced duplicate paths";
in
builtins.seq _haveSiteData (builtins.seq _uniquePaths (builtins.listToAttrs contextEntries))
