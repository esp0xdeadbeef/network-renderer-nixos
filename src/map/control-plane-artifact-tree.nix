{ lib }:
{
  normalizedModel,
  controlPlaneOut,
  includeFullModel ? true,
  fullModelFileName ? "control-plane-model.json",
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

  rootFileName = validPathSegment "artifact file name" fullModelFileName;

  strippedControlPlaneOut = builtins.removeAttrs controlPlaneOut [
    "fabricInputs"
    "globalInventory"
  ];

  sourceRoot =
    if
      strippedControlPlaneOut ? control_plane_model
      && builtins.isAttrs strippedControlPlaneOut.control_plane_model
    then
      strippedControlPlaneOut.control_plane_model
    else if
      strippedControlPlaneOut ? controlPlaneModel
      && builtins.isAttrs strippedControlPlaneOut.controlPlaneModel
    then
      strippedControlPlaneOut.controlPlaneModel
    else
      throw "network-renderer-nixos: split artifact source must expose control_plane_model";

  siteData =
    if sourceRoot ? data then
      ensureAttrs "control_plane_model.data" sourceRoot.data
    else
      ensureAttrs "control_plane_model.data" normalizedModel.siteData;

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

  runtimeTargetCarriesContainerServices =
    runtimeTarget:
    runtimeTarget ? advertisements
    && builtins.isAttrs runtimeTarget.advertisements
    && runtimeTarget.advertisements != { };

  impliedContainerNameForRuntimeTarget =
    runtimeTargetName: runtimeTarget:
    if runtimeTargetCarriesContainerServices runtimeTarget then
      validPathSegment "implied container name for runtime target '${runtimeTargetName}'" runtimeTargetName
    else
      null;

  normalizeContainerNameForRuntimeTarget =
    runtimeTargetName: containerValue:
    if builtins.isString containerValue then
      validPathSegment "container name for runtime target '${runtimeTargetName}'" containerValue
    else
      let
        container = ensureAttrs "control_plane_model.data.*.*.runtimeTargets.${runtimeTargetName}.containers entry" containerValue;
      in
      if container ? runtimeName then
        validPathSegment "runtime container name for runtime target '${runtimeTargetName}'" container.runtimeName
      else if container ? container then
        validPathSegment "container field for runtime target '${runtimeTargetName}'" container.container
      else if container ? name then
        validPathSegment "container name for runtime target '${runtimeTargetName}'" container.name
      else if container ? logicalName then
        validPathSegment "logical container name for runtime target '${runtimeTargetName}'" container.logicalName
      else
        throw "network-renderer-nixos: runtime target '${runtimeTargetName}' container entry must define runtimeName, container, name, or logicalName";

  containerNamesForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    let
      explicitContainerNames =
        if runtimeTarget ? containers then
          let
            entries = ensureList "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets.${runtimeTargetName}.containers" runtimeTarget.containers;
          in
          map (
            containerValue: normalizeContainerNameForRuntimeTarget runtimeTargetName containerValue
          ) entries
        else
          [ ];

      containerNames =
        if explicitContainerNames != [ ] then
          explicitContainerNames
        else
          lib.optional (impliedContainerNameForRuntimeTarget runtimeTargetName runtimeTarget != null) (
            impliedContainerNameForRuntimeTarget runtimeTargetName runtimeTarget
          );

      uniqueContainerNames = lib.unique containerNames;

      _uniqueContainerNames =
        if builtins.length containerNames == builtins.length uniqueContainerNames then
          true
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' defines duplicate container names";
    in
    builtins.seq _uniqueContainerNames uniqueContainerNames;

  groupRuntimeTargetsByHost =
    enterpriseName: siteName: runtimeTargets:
    builtins.foldl' (
      acc: runtimeTargetName:
      let
        runtimeTarget = runtimeTargets.${runtimeTargetName};
        hostName = hostNameForRuntimeTarget enterpriseName siteName runtimeTargetName runtimeTarget;
      in
      acc
      // {
        "${hostName}" = (acc.${hostName} or { }) // {
          "${runtimeTargetName}" = runtimeTarget;
        };
      }
    ) { } (sortedAttrNames runtimeTargets);

  groupRuntimeTargetsByContainer =
    enterpriseName: siteName: runtimeTargets:
    builtins.foldl' (
      acc: runtimeTargetName:
      let
        runtimeTarget = runtimeTargets.${runtimeTargetName};
        containerNames =
          containerNamesForRuntimeTarget enterpriseName siteName runtimeTargetName
            runtimeTarget;
      in
      builtins.foldl' (
        innerAcc: containerName:
        innerAcc
        // {
          "${containerName}" = (innerAcc.${containerName} or { }) // {
            "${runtimeTargetName}" = runtimeTarget;
          };
        }
      ) acc containerNames
    ) { } (sortedAttrNames runtimeTargets);

  filterRuntimeTargets =
    predicate: runtimeTargets:
    builtins.listToAttrs (
      lib.concatMap (
        runtimeTargetName:
        let
          runtimeTarget = runtimeTargets.${runtimeTargetName};
        in
        if predicate runtimeTargetName runtimeTarget then
          [
            {
              name = runtimeTargetName;
              value = runtimeTarget;
            }
          ]
        else
          [ ]
      ) (sortedAttrNames runtimeTargets)
    );

  hostScopedRuntimeTargetsForSite =
    enterpriseName: siteName: runtimeTargets:
    filterRuntimeTargets (
      runtimeTargetName: runtimeTarget:
      containerNamesForRuntimeTarget enterpriseName siteName runtimeTargetName runtimeTarget == [ ]
    ) runtimeTargets;

  hostDataAndContainersRoot = hostPath: "${hostPath}/host-data-and-containers";
  hostDataPath = hostPath: "${hostDataAndContainersRoot hostPath}/host-data";
  containersPath = hostPath: "${hostDataAndContainersRoot hostPath}/containers";
  hostArtifactPath = hostPath: "${hostDataPath hostPath}/host.json";
  containerArtifactPath =
    hostPath: containerName: "${containersPath hostPath}/${containerName}/container.json";

  hostRuntimeTargetArtifactPath =
    hostPath: runtimeTargetName:
    let
      runtimeTargetSegment = validPathSegment "runtime target name" runtimeTargetName;
    in
    "${hostDataPath hostPath}/runtime-targets/${runtimeTargetSegment}/runtime-target.json";

  containerRuntimeTargetArtifactPath =
    hostPath: containerName: runtimeTargetName:
    let
      runtimeTargetSegment = validPathSegment "runtime target name" runtimeTargetName;
    in
    "${containersPath hostPath}/${containerName}/runtime-targets/${runtimeTargetSegment}/runtime-target.json";

  jsonFileEntry = name: value: {
    inherit name;
    value = {
      format = "json";
      inherit value;
    };
  };

  hostEntries = lib.concatMap (
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
        runtimeTargetsByHost = groupRuntimeTargetsByHost enterpriseName siteName runtimeTargets;
        hostScopedRuntimeTargets = hostScopedRuntimeTargetsForSite enterpriseName siteName runtimeTargets;
        hostScopedRuntimeTargetsByHost =
          groupRuntimeTargetsByHost enterpriseName siteName
            hostScopedRuntimeTargets;
      in
      lib.concatMap (
        hostName:
        let
          hostSegment = validPathSegment "host name" hostName;
          hostPath = "${sitePath}/${hostSegment}";
          hostRuntimeTargets = hostScopedRuntimeTargetsByHost.${hostName} or { };
          hostRuntimeTargetNames = sortedAttrNames hostRuntimeTargets;
          hostRuntimeTargetArtifactPaths = map (
            runtimeTargetName: hostRuntimeTargetArtifactPath hostPath runtimeTargetName
          ) hostRuntimeTargetNames;

          hostAllRuntimeTargets = runtimeTargetsByHost.${hostName};
          containerRuntimeTargets =
            groupRuntimeTargetsByContainer enterpriseName siteName
              hostAllRuntimeTargets;
          containerNames = sortedAttrNames containerRuntimeTargets;

          containerSummaries = builtins.listToAttrs (
            map (
              containerName:
              let
                containerRuntimeTargetMap = containerRuntimeTargets.${containerName};
                containerRuntimeTargetNames = sortedAttrNames containerRuntimeTargetMap;
                containerRuntimeTargetArtifactPaths = map (
                  runtimeTargetName: containerRuntimeTargetArtifactPath hostPath containerName runtimeTargetName
                ) containerRuntimeTargetNames;
              in
              {
                name = containerName;
                value = {
                  artifactPath = containerArtifactPath hostPath containerName;
                  runtimeTargetNames = containerRuntimeTargetNames;
                  runtimeTargetArtifactPaths = containerRuntimeTargetArtifactPaths;
                };
              }
            ) containerNames
          );

          allRuntimeTargetNames = lib.unique (
            hostRuntimeTargetNames
            ++ lib.concatMap (
              containerName: containerSummaries.${containerName}.runtimeTargetNames
            ) containerNames
          );

          allRuntimeTargetArtifactPaths = lib.unique (
            hostRuntimeTargetArtifactPaths
            ++ lib.concatMap (
              containerName: containerSummaries.${containerName}.runtimeTargetArtifactPaths
            ) containerNames
          );

          hostSummary = {
            enterprise = enterpriseName;
            site = siteName;
            host = hostName;
            artifactPath = hostArtifactPath hostPath;
            runtimeTargetNames = hostRuntimeTargetNames;
            runtimeTargetArtifactPaths = hostRuntimeTargetArtifactPaths;
            containerNames = containerNames;
            containerArtifactPaths = map (
              containerName: containerArtifactPath hostPath containerName
            ) containerNames;
            containers = containerSummaries;
            allRuntimeTargetNames = allRuntimeTargetNames;
            allRuntimeTargetArtifactPaths = allRuntimeTargetArtifactPaths;
          };

          runtimeTargetEntries = lib.concatMap (runtimeTargetName: [
            (jsonFileEntry (hostRuntimeTargetArtifactPath hostPath runtimeTargetName)
              hostRuntimeTargets.${runtimeTargetName}
            )
          ]) hostRuntimeTargetNames;

          containerEntries = lib.concatMap (
            containerName:
            let
              containerRuntimeTargetMap = containerRuntimeTargets.${containerName};
              containerRuntimeTargetNames = sortedAttrNames containerRuntimeTargetMap;

              containerSummary = {
                enterprise = enterpriseName;
                site = siteName;
                host = hostName;
                container = containerName;
                artifactPath = containerArtifactPath hostPath containerName;
                runtimeTargetNames = containerRuntimeTargetNames;
                runtimeTargetArtifactPaths = map (
                  runtimeTargetName: containerRuntimeTargetArtifactPath hostPath containerName runtimeTargetName
                ) containerRuntimeTargetNames;
              };

              containerRuntimeTargetEntries = lib.concatMap (runtimeTargetName: [
                (jsonFileEntry (containerRuntimeTargetArtifactPath hostPath containerName
                  runtimeTargetName
                ) containerRuntimeTargetMap.${runtimeTargetName})
              ]) containerRuntimeTargetNames;
            in
            [
              (jsonFileEntry (containerArtifactPath hostPath containerName) containerSummary)
            ]
            ++ containerRuntimeTargetEntries
          ) containerNames;
        in
        [
          (jsonFileEntry (hostArtifactPath hostPath) hostSummary)
        ]
        ++ runtimeTargetEntries
        ++ containerEntries
      ) (sortedAttrNames runtimeTargetsByHost)
    ) (sortedAttrNames enterpriseSites)
  ) (sortedAttrNames siteData);

  fileEntries =
    (lib.optional includeFullModel (jsonFileEntry rootFileName strippedControlPlaneOut)) ++ hostEntries;

  filePaths = map (entry: entry.name) fileEntries;

  _uniquePaths =
    if builtins.length filePaths == builtins.length (lib.unique filePaths) then
      true
    else
      throw "network-renderer-nixos: artifact file mapping produced duplicate paths";
in
builtins.seq _haveSiteData (builtins.seq _uniquePaths (builtins.listToAttrs fileEntries))
