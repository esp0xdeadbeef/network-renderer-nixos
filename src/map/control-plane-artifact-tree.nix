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
      runtimeTarget.placement.host;

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

  filterRuntimeTargets =
    enterpriseName: siteName: predicate: runtimeTargets:
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
    filterRuntimeTargets enterpriseName siteName (
      runtimeTargetName: runtimeTarget:
      containerNamesForRuntimeTarget enterpriseName siteName runtimeTargetName runtimeTarget == [ ]
    ) runtimeTargets;

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

  fileEntry = name: value: {
    inherit name value;
  };

  jsonFileEntry =
    name: value:
    fileEntry name {
      format = "json";
      inherit value;
    };

  siteArtifactPath = sitePath: "${sitePath}/site.json";
  siteDataArtifactPath = sitePath: "${sitePath}/site-data.json";
  hostArtifactPath = hostPath: "${hostPath}/host.json";
  containerArtifactPath =
    hostPath: containerName: "${hostPath}/containers/${containerName}/container.json";

  hostRuntimeTargetArtifactPath =
    hostPath: runtimeTargetName:
    let
      runtimeTargetSegment = validPathSegment "runtime target name" runtimeTargetName;
    in
    "${hostPath}/runtime-targets/${runtimeTargetSegment}/runtime-target.json";

  containerRuntimeTargetArtifactPath =
    hostPath: containerName: runtimeTargetName:
    let
      runtimeTargetSegment = validPathSegment "runtime target name" runtimeTargetName;
    in
    "${hostPath}/containers/${containerName}/runtime-targets/${runtimeTargetSegment}/runtime-target.json";

  enterpriseEntries = lib.concatMap (
    enterpriseName:
    let
      enterpriseSegment = validPathSegment "enterprise name" enterpriseName;
      enterpriseSites =
        ensureAttrs "control_plane_model.data.${enterpriseName}"
          siteData.${enterpriseName};
      siteNames = sortedAttrNames enterpriseSites;

      siteEntries = lib.concatMap (
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
          hostNames = sortedAttrNames runtimeTargetsByHost;

          hostSummaries = builtins.listToAttrs (
            map (
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
              in
              {
                name = hostName;
                value = {
                  artifactPath = hostArtifactPath hostPath;
                  runtimeTargetNames = hostRuntimeTargetNames;
                  runtimeTargetArtifactPaths = hostRuntimeTargetArtifactPaths;
                  containerNames = containerNames;
                  containerArtifactPaths = map (
                    containerName: containerArtifactPath hostPath containerName
                  ) containerNames;
                  containerRuntimeTargets = containerSummaries;
                  allRuntimeTargetNames = allRuntimeTargetNames;
                  allRuntimeTargetArtifactPaths = allRuntimeTargetArtifactPaths;
                };
              }
            ) hostNames
          );

          hostEntries = lib.concatMap (
            hostName:
            let
              hostSegment = validPathSegment "host name" hostName;
              hostPath = "${sitePath}/${hostSegment}";
              hostRuntimeTargets = hostScopedRuntimeTargetsByHost.${hostName} or { };
              hostRuntimeTargetNames = sortedAttrNames hostRuntimeTargets;
              hostAllRuntimeTargets = runtimeTargetsByHost.${hostName};
              containerRuntimeTargets =
                groupRuntimeTargetsByContainer enterpriseName siteName
                  hostAllRuntimeTargets;
              containerNames = sortedAttrNames containerRuntimeTargets;

              runtimeTargetEntries = lib.concatMap (runtimeTargetName: [
                (jsonFileEntry (hostRuntimeTargetArtifactPath hostPath runtimeTargetName)
                  hostRuntimeTargets.${runtimeTargetName}
                )
              ]) hostRuntimeTargetNames;

              containerEntries = lib.concatMap (
                containerName:
                let
                  containerPath = "${hostPath}/containers/${containerName}";
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
                  (jsonFileEntry "${containerPath}/container.json" containerSummary)
                ]
                ++ containerRuntimeTargetEntries
              ) containerNames;

              hostSummary = {
                enterprise = enterpriseName;
                site = siteName;
                host = hostName;
                artifactPath = hostArtifactPath hostPath;
                runtimeTargetNames = hostRuntimeTargetNames;
                runtimeTargetArtifactPaths = hostSummaries.${hostName}.runtimeTargetArtifactPaths;
                containerNames = containerNames;
                containerArtifactPaths = hostSummaries.${hostName}.containerArtifactPaths;
                containerRuntimeTargets = hostSummaries.${hostName}.containerRuntimeTargets;
                allRuntimeTargetNames = hostSummaries.${hostName}.allRuntimeTargetNames;
                allRuntimeTargetArtifactPaths = hostSummaries.${hostName}.allRuntimeTargetArtifactPaths;
              };
            in
            [
              (jsonFileEntry "${hostPath}/host.json" hostSummary)
            ]
            ++ runtimeTargetEntries
            ++ containerEntries
          ) hostNames;

          siteSummary = {
            enterprise = enterpriseName;
            site = siteName;
            artifactPath = siteArtifactPath sitePath;
            siteDataArtifactPath = siteDataArtifactPath sitePath;
            hostNames = hostNames;
            hostArtifactPaths = map (
              hostName:
              let
                hostSegment = validPathSegment "host name" hostName;
              in
              hostArtifactPath "${sitePath}/${hostSegment}"
            ) hostNames;
            runtimeTargetNames = sortedAttrNames runtimeTargets;
          };
        in
        [
          (jsonFileEntry "${sitePath}/site.json" siteSummary)
          (jsonFileEntry "${sitePath}/site-data.json" site)
        ]
        ++ hostEntries
      ) siteNames;

      enterpriseSummary = {
        enterprise = enterpriseName;
        siteNames = siteNames;
      };
    in
    [
      (jsonFileEntry "${enterpriseSegment}/enterprise.json" enterpriseSummary)
    ]
    ++ siteEntries
  ) (sortedAttrNames siteData);

  fileEntries =
    (lib.optional includeFullModel (jsonFileEntry rootFileName strippedControlPlaneOut))
    ++ enterpriseEntries;

  filePaths = map (entry: entry.name) fileEntries;

  _uniquePaths =
    if builtins.length filePaths == builtins.length (lib.unique filePaths) then
      true
    else
      throw "network-renderer-nixos: artifact file mapping produced duplicate paths";
in
builtins.seq _haveSiteData (builtins.seq _uniquePaths (builtins.listToAttrs fileEntries))
