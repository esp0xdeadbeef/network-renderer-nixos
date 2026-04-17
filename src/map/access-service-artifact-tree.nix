{
  lib,
  mapRuntimeTargetArtifactContexts,
  selectContainerRuntimeTargetServiceModels,
}:
{ normalizedModel }:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  safeJson =
    value:
    let
      rendered = builtins.tryEval (builtins.toJSON value);
    in
    if rendered.success then rendered.value else "\"<non-jsonable:${builtins.typeOf value}>\"";

  throwWithValue =
    message: value:
    throw ''
      ${message}
      value=${safeJson value}
    '';

  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throwWithValue "network-renderer-nixos: expected ${name} to be an attribute set" value;

  ensureBool =
    name: value:
    if builtins.isBool value then
      value
    else
      throwWithValue "network-renderer-nixos: expected ${name} to be a boolean" value;

  ensureInt =
    name: value:
    if builtins.isInt value then
      value
    else
      throwWithValue "network-renderer-nixos: expected ${name} to be an integer" value;

  ensureList =
    name: value:
    if builtins.isList value then
      value
    else
      throwWithValue "network-renderer-nixos: expected ${name} to be a list" value;

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throwWithValue "network-renderer-nixos: expected ${name} to be a non-empty string" value;

  compactAttrs = attrs: lib.filterAttrs (_: value: value != null) attrs;

  normalizeOptionalString = name: value: if value == null then null else ensureString name value;

  normalizeOptionalBool = name: value: if value == null then null else ensureBool name value;

  normalizeOptionalInt = name: value: if value == null then null else ensureInt name value;

  normalizeStringList =
    name: value: map (entry: ensureString "${name} entry" entry) (ensureList name value);

  normalizeRouterInterface =
    name: value:
    if value == null then
      null
    else
      let
        routerInterface = ensureAttrs name value;
      in
      compactAttrs {
        interface = normalizeOptionalString "${name}.interface" (routerInterface.interface or null);
        bindInterface = normalizeOptionalString "${name}.bindInterface" (
          routerInterface.bindInterface or null
        );
        address4 = normalizeOptionalString "${name}.address4" (routerInterface.address4 or null);
        address6 = normalizeOptionalString "${name}.address6" (routerInterface.address6 or null);
        subnet4 = normalizeOptionalString "${name}.subnet4" (routerInterface.subnet4 or null);
        subnet6 = normalizeOptionalString "${name}.subnet6" (routerInterface.subnet6 or null);
        tenant = normalizeOptionalString "${name}.tenant" (routerInterface.tenant or null);
      };

  normalizeKeaPool =
    name: value:
    let
      pool = ensureAttrs name value;
    in
    {
      start = ensureString "${name}.start" pool.start;
      end = ensureString "${name}.end" pool.end;
    };

  normalizeKeaScope =
    runtimeTargetName: scopeIndex: value:
    let
      scope = ensureAttrs "kea scope ${toString scopeIndex} for runtime target '${runtimeTargetName}'" value;

      pools =
        map
          (
            pool:
            normalizeKeaPool "kea scope ${toString scopeIndex}.pools for runtime target '${runtimeTargetName}'" pool
          )
          (
            ensureList "kea scope ${toString scopeIndex}.pools for runtime target '${runtimeTargetName}'" scope.pools
          );
    in
    compactAttrs {
      advertisementId =
        normalizeOptionalString
          "kea scope ${toString scopeIndex}.advertisementId for runtime target '${runtimeTargetName}'"
          (scope.advertisementId or null);
      interfaceName = ensureString "kea scope ${toString scopeIndex}.interfaceName for runtime target '${runtimeTargetName}'" scope.interfaceName;
      subnet = ensureString "kea scope ${toString scopeIndex}.subnet for runtime target '${runtimeTargetName}'" scope.subnet;
      subnetId =
        normalizeOptionalInt
          "kea scope ${toString scopeIndex}.subnetId for runtime target '${runtimeTargetName}'"
          (scope.subnetId or null);
      pools = pools;
      routers =
        if scope ? routers then
          normalizeStringList "kea scope ${toString scopeIndex}.routers for runtime target '${runtimeTargetName}'" scope.routers
        else
          [ ];
      dnsServers =
        if scope ? dnsServers then
          normalizeStringList "kea scope ${toString scopeIndex}.dnsServers for runtime target '${runtimeTargetName}'" scope.dnsServers
        else
          [ ];
      domain =
        normalizeOptionalString
          "kea scope ${toString scopeIndex}.domain for runtime target '${runtimeTargetName}'"
          (scope.domain or null);
      tenant =
        normalizeOptionalString
          "kea scope ${toString scopeIndex}.tenant for runtime target '${runtimeTargetName}'"
          (scope.tenant or null);
      routerInterface =
        normalizeRouterInterface
          "kea scope ${toString scopeIndex}.routerInterface for runtime target '${runtimeTargetName}'"
          (scope.routerInterface or null);
      routerInterfaceAddress =
        normalizeOptionalString
          "kea scope ${toString scopeIndex}.routerInterfaceAddress for runtime target '${runtimeTargetName}'"
          (scope.routerInterfaceAddress or null);
    };

  normalizeRadvdPrefix =
    name: value:
    let
      prefix = ensureAttrs name value;
    in
    compactAttrs {
      prefix = ensureString "${name}.prefix" prefix.prefix;
      advOnLink = normalizeOptionalBool "${name}.advOnLink" (prefix.advOnLink or null);
      advAutonomous = normalizeOptionalBool "${name}.advAutonomous" (prefix.advAutonomous or null);
    };

  normalizeRadvdAdvertisement =
    runtimeTargetName: advertisementIndex: value:
    let
      advertisement = ensureAttrs "radvd advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}'" value;

      prefixes =
        map
          (
            prefix:
            normalizeRadvdPrefix "radvd advertisement ${toString advertisementIndex}.prefixes for runtime target '${runtimeTargetName}'" prefix
          )
          (
            ensureList "radvd advertisement ${toString advertisementIndex}.prefixes for runtime target '${runtimeTargetName}'" advertisement.prefixes
          );
    in
    compactAttrs {
      advertisementId =
        normalizeOptionalString
          "radvd advertisement ${toString advertisementIndex}.advertisementId for runtime target '${runtimeTargetName}'"
          (advertisement.advertisementId or null);
      interfaceName = ensureString "radvd advertisement ${toString advertisementIndex}.interfaceName for runtime target '${runtimeTargetName}'" advertisement.interfaceName;
      prefixes = prefixes;
      rdnss =
        if advertisement ? rdnss then
          normalizeStringList "radvd advertisement ${toString advertisementIndex}.rdnss for runtime target '${runtimeTargetName}'" advertisement.rdnss
        else
          [ ];
      dnssl =
        if advertisement ? dnssl then
          normalizeStringList "radvd advertisement ${toString advertisementIndex}.dnssl for runtime target '${runtimeTargetName}'" advertisement.dnssl
        else
          [ ];
      tenant =
        normalizeOptionalString
          "radvd advertisement ${toString advertisementIndex}.tenant for runtime target '${runtimeTargetName}'"
          (advertisement.tenant or null);
      advManagedFlag =
        normalizeOptionalBool
          "radvd advertisement ${toString advertisementIndex}.advManagedFlag for runtime target '${runtimeTargetName}'"
          (advertisement.advManagedFlag or null);
      advOtherConfigFlag =
        normalizeOptionalBool
          "radvd advertisement ${toString advertisementIndex}.advOtherConfigFlag for runtime target '${runtimeTargetName}'"
          (advertisement.advOtherConfigFlag or null);
      minRtrAdvInterval =
        normalizeOptionalInt
          "radvd advertisement ${toString advertisementIndex}.minRtrAdvInterval for runtime target '${runtimeTargetName}'"
          (advertisement.minRtrAdvInterval or null);
      maxRtrAdvInterval =
        normalizeOptionalInt
          "radvd advertisement ${toString advertisementIndex}.maxRtrAdvInterval for runtime target '${runtimeTargetName}'"
          (advertisement.maxRtrAdvInterval or null);
      routerInterface =
        normalizeRouterInterface
          "radvd advertisement ${toString advertisementIndex}.routerInterface for runtime target '${runtimeTargetName}'"
          (advertisement.routerInterface or null);
      routerInterfaceAddress =
        normalizeOptionalString
          "radvd advertisement ${toString advertisementIndex}.routerInterfaceAddress for runtime target '${runtimeTargetName}'"
          (advertisement.routerInterfaceAddress or null);
    };

  normalizeServiceRuntimeTargetModel =
    serviceName: maybeModel:
    let
      model = ensureAttrs "${serviceName} runtime target service model" maybeModel;

      normalizedCommon = {
        service = ensureString "${serviceName} runtime target service model.service" model.service;
        enterprise = ensureString "${serviceName} runtime target service model.enterprise" model.enterprise;
        site = ensureString "${serviceName} runtime target service model.site" model.site;
        host = ensureString "${serviceName} runtime target service model.host" model.host;
        container = ensureString "${serviceName} runtime target service model.container" model.container;
        runtimeTargetName = ensureString "${serviceName} runtime target service model.runtimeTargetName" model.runtimeTargetName;
        runtimeTargetArtifactPath = ensureString "${serviceName} runtime target service model.runtimeTargetArtifactPath" model.runtimeTargetArtifactPath;
      };
    in
    if serviceName == "kea" then
      let
        scopes =
          map
            (
              scopeIndex:
              normalizeKeaScope normalizedCommon.runtimeTargetName scopeIndex (
                builtins.elemAt (ensureList "${serviceName} runtime target service model.scopes" model.scopes) scopeIndex
              )
            )
            (
              lib.range 0 (
                (builtins.length (ensureList "${serviceName} runtime target service model.scopes" model.scopes)) - 1
              )
            );
      in
      normalizedCommon
      // {
        scopes = scopes;
      }
    else if serviceName == "radvd" then
      let
        advertisements =
          map
            (
              advertisementIndex:
              normalizeRadvdAdvertisement normalizedCommon.runtimeTargetName advertisementIndex (
                builtins.elemAt (ensureList "${serviceName} runtime target service model.advertisements" model.advertisements) advertisementIndex
              )
            )
            (
              lib.range 0 (
                (builtins.length (
                  ensureList "${serviceName} runtime target service model.advertisements" model.advertisements
                ))
                - 1
              )
            );
      in
      normalizedCommon
      // {
        advertisements = advertisements;
      }
    else
      throw "network-renderer-nixos: unsupported access service '${serviceName}'";

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

  runtimeTargetContexts = mapRuntimeTargetArtifactContexts { inherit normalizedModel; };

  serviceArtifactPath =
    serviceName: model:
    let
      serviceSegment = validPathSegment "service name" serviceName;
      enterpriseSegment = validPathSegment "enterprise name" model.enterprise;
      siteSegment = validPathSegment "site name" model.site;
      hostSegment = validPathSegment "host name" model.host;
      containerSegment = validPathSegment "container name" model.container;
    in
    "${enterpriseSegment}/${siteSegment}/${hostSegment}/host-data-and-containers/containers/${containerSegment}/services/${serviceSegment}/${serviceSegment}.json";

  serviceIndexPath =
    model:
    let
      enterpriseSegment = validPathSegment "enterprise name" model.enterprise;
      siteSegment = validPathSegment "site name" model.site;
      hostSegment = validPathSegment "host name" model.host;
      containerSegment = validPathSegment "container name" model.container;
    in
    "${enterpriseSegment}/${siteSegment}/${hostSegment}/host-data-and-containers/containers/${containerSegment}/services/index.json";

  sortRuntimeTargets =
    runtimeTargets:
    lib.sort (
      left: right:
      let
        leftName = ensureString "runtime target service model.runtimeTargetName" left.runtimeTargetName;
        rightName = ensureString "runtime target service model.runtimeTargetName" right.runtimeTargetName;
        leftPath = ensureString "runtime target service model.runtimeTargetArtifactPath" left.runtimeTargetArtifactPath;
        rightPath = ensureString "runtime target service model.runtimeTargetArtifactPath" right.runtimeTargetArtifactPath;
      in
      if leftName == rightName then leftPath < rightPath else leftName < rightName
    ) runtimeTargets;

  appendServiceModel =
    acc: serviceName: maybeModel:
    if maybeModel == null then
      acc
    else
      let
        model = normalizeServiceRuntimeTargetModel serviceName maybeModel;
        path = serviceArtifactPath serviceName model;
        runtimeTargetName = ensureString "${serviceName} runtime target service model.runtimeTargetName" model.runtimeTargetName;
      in
      if builtins.hasAttr path acc then
        let
          existing = acc.${path};
          existingRuntimeTargetNames = map (entry: entry.runtimeTargetName) existing.runtimeTargets;

          _sameContainer =
            if
              existing.service == serviceName
              && existing.enterprise == model.enterprise
              && existing.site == model.site
              && existing.host == model.host
              && existing.container == model.container
            then
              true
            else
              throw ''
                network-renderer-nixos: service artifact aggregation for '${path}' resolved inconsistent container scope
                existing=${safeJson existing}
                incoming=${safeJson model}
              '';

          _uniqueRuntimeTarget =
            if lib.elem runtimeTargetName existingRuntimeTargetNames then
              throw ''
                network-renderer-nixos: service artifact aggregation for '${path}' produced duplicate runtime target '${runtimeTargetName}'
                existing=${safeJson existing}
                incoming=${safeJson model}
              ''
            else
              true;
        in
        builtins.seq _sameContainer (
          builtins.seq _uniqueRuntimeTarget (
            acc
            // {
              "${path}" = existing // {
                runtimeTargets = existing.runtimeTargets ++ [ model ];
              };
            }
          )
        )
      else
        acc
        // {
          "${path}" = {
            service = serviceName;
            enterprise = ensureString "${serviceName} runtime target service model.enterprise" model.enterprise;
            site = ensureString "${serviceName} runtime target service model.site" model.site;
            host = ensureString "${serviceName} runtime target service model.host" model.host;
            container = ensureString "${serviceName} runtime target service model.container" model.container;
            artifactPath = path;
            runtimeTargets = [ model ];
          };
        };

  aggregatedServiceFiles = builtins.foldl' (
    acc: contextName:
    let
      context = runtimeTargetContexts.${contextName};
      selectedModels = selectContainerRuntimeTargetServiceModels { artifactContext = context; };
    in
    appendServiceModel (appendServiceModel acc "kea" selectedModels.kea) "radvd" selectedModels.radvd
  ) { } (sortedAttrNames runtimeTargetContexts);

  renderedServiceFiles = builtins.mapAttrs (
    path: entry:
    let
      sortedRuntimeTargets = sortRuntimeTargets entry.runtimeTargets;
    in
    {
      format = "json";
      value = entry // {
        runtimeTargets = sortedRuntimeTargets;
        runtimeTargetNames = map (model: model.runtimeTargetName) sortedRuntimeTargets;
        runtimeTargetArtifactPaths = map (model: model.runtimeTargetArtifactPath) sortedRuntimeTargets;
      };
    }
  ) aggregatedServiceFiles;

  renderedIndexFiles = builtins.foldl' (
    acc: servicePath:
    let
      serviceEntry = renderedServiceFiles.${servicePath}.value;
      indexPath = serviceIndexPath serviceEntry;

      serviceSummary = {
        artifactPath = servicePath;
        runtimeTargetNames = serviceEntry.runtimeTargetNames;
        runtimeTargetArtifactPaths = serviceEntry.runtimeTargetArtifactPaths;
      };
    in
    if builtins.hasAttr indexPath acc then
      let
        existing = acc.${indexPath}.value;
      in
      acc
      // {
        "${indexPath}" = {
          format = "json";
          value = existing // {
            serviceNames = lib.sort builtins.lessThan (
              lib.unique (existing.serviceNames ++ [ serviceEntry.service ])
            );
            services = existing.services // {
              "${serviceEntry.service}" = serviceSummary;
            };
          };
        };
      }
    else
      acc
      // {
        "${indexPath}" = {
          format = "json";
          value = {
            enterprise = serviceEntry.enterprise;
            site = serviceEntry.site;
            host = serviceEntry.host;
            container = serviceEntry.container;
            artifactPath = indexPath;
            serviceNames = [ serviceEntry.service ];
            services = {
              "${serviceEntry.service}" = serviceSummary;
            };
          };
        };
      }
  ) { } (sortedAttrNames renderedServiceFiles);

  mergedFiles = renderedServiceFiles // renderedIndexFiles;
  mergedPaths = builtins.attrNames mergedFiles;

  _uniqueMergedPaths =
    if builtins.length mergedPaths == builtins.length (lib.unique mergedPaths) then
      true
    else
      throw "network-renderer-nixos: access service artifact rendering produced duplicate output paths";
in
builtins.seq _uniqueMergedPaths mergedFiles
