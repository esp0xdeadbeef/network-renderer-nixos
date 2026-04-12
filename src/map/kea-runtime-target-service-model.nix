{ lib }:
{
  artifactContext,
  advertisements,
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeForJson =
    depth: value:
    let
      valueType = builtins.typeOf value;
    in
    if depth >= 6 then
      if valueType == "set" then
        {
          __type = "set";
          __keys = sortedAttrNames value;
        }
      else if valueType == "list" then
        {
          __type = "list";
          __length = builtins.length value;
        }
      else if valueType == "lambda" then
        "<function>"
      else if valueType == "path" then
        toString value
      else
        value
    else if valueType == "set" then
      builtins.listToAttrs (
        map (name: {
          inherit name;
          value = sanitizeForJson (depth + 1) value.${name};
        }) (sortedAttrNames value)
      )
    else if valueType == "list" then
      map (entry: sanitizeForJson (depth + 1) entry) value
    else if valueType == "lambda" then
      "<function>"
    else if valueType == "path" then
      toString value
    else
      value;

  safeJson = value: builtins.toJSON (sanitizeForJson 0 value);

  throwWithValue =
    message: value:
    throw ''
      ${message}
      value=${safeJson value}
    '';

  ensureJsonableWithSource =
    name: value: source:
    let
      rendered = builtins.tryEval (builtins.toJSON value);
    in
    if rendered.success then
      true
    else
      throw ''
        network-renderer-nixos: ${name} is not JSON-serializable
        value=${safeJson value}
        source=${safeJson source}
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

  normalizeOptionalInt = name: value: if value == null then null else ensureInt name value;

  normalizeAddressValue =
    name: value:
    if builtins.isString value then
      ensureString name value
    else
      let
        valueDef = ensureAttrs name value;
      in
      if valueDef ? address then
        ensureString "${name}.address" valueDef.address
      else if valueDef ? address4 then
        ensureString "${name}.address4" valueDef.address4
      else if valueDef ? address6 then
        ensureString "${name}.address6" valueDef.address6
      else if valueDef ? ipv4 then
        ensureString "${name}.ipv4" valueDef.ipv4
      else if valueDef ? ipv6 then
        ensureString "${name}.ipv6" valueDef.ipv6
      else if valueDef ? ip then
        ensureString "${name}.ip" valueDef.ip
      else if valueDef ? value then
        ensureString "${name}.value" valueDef.value
      else
        throwWithValue "network-renderer-nixos: expected ${name} to resolve to a non-empty address string" value;

  normalizeOptionalAddressList =
    name: value:
    if value == null then
      [ ]
    else if builtins.isList value then
      map (entry: normalizeAddressValue "${name} entry" entry) (ensureList name value)
    else
      [ (normalizeAddressValue name value) ];

  normalizeOptionalRouterInterface =
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

  normalizePoolRange =
    name: value:
    let
      pool = ensureAttrs name value;
    in
    {
      start = ensureString "${name}.start" pool.start;
      end = ensureString "${name}.end" pool.end;
    };

  resolveInterfaceName =
    runtimeTargetName: advertisementIndex: advertisement:
    let
      advertisementDef = ensureAttrs "Kea advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}'" advertisement;

      routerInterface =
        if advertisementDef ? routerInterface then
          ensureAttrs "Kea advertisement ${toString advertisementIndex} routerInterface for runtime target '${runtimeTargetName}'" advertisementDef.routerInterface
        else
          { };
    in
    if advertisementDef ? bindInterface then
      ensureString "Kea advertisement ${toString advertisementIndex}.bindInterface for runtime target '${runtimeTargetName}'" advertisementDef.bindInterface
    else if advertisementDef ? interface then
      ensureString "Kea advertisement ${toString advertisementIndex}.interface for runtime target '${runtimeTargetName}'" advertisementDef.interface
    else if routerInterface ? bindInterface then
      ensureString "Kea advertisement ${toString advertisementIndex}.routerInterface.bindInterface for runtime target '${runtimeTargetName}'" routerInterface.bindInterface
    else if routerInterface ? interface then
      ensureString "Kea advertisement ${toString advertisementIndex}.routerInterface.interface for runtime target '${runtimeTargetName}'" routerInterface.interface
    else
      throw ''
        network-renderer-nixos: Kea advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}' is missing bindInterface/interface
        advertisement=${safeJson advertisementDef}
      '';

  context = ensureAttrs "artifactContext" artifactContext;

  enterprise = ensureString "artifactContext.enterpriseName" context.enterpriseName;
  site = ensureString "artifactContext.siteName" context.siteName;
  host = ensureString "artifactContext.hostName" context.hostName;
  container = ensureString "artifactContext.containerName" context.containerName;
  runtimeTargetName = ensureString "artifactContext.runtimeTargetName" context.runtimeTargetName;
  runtimeTargetArtifactPath = ensureString "artifactContext.runtimeTargetArtifactPath" context.runtimeTargetArtifactPath;

  advertisementList = ensureList "Kea advertisements" advertisements;

  normalizedAdvertisements = map (
    advertisementIndex:
    let
      advertisement = builtins.elemAt advertisementList advertisementIndex;

      advertisementDef = ensureAttrs "Kea advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}'" advertisement;

      enabled =
        if advertisementDef ? enabled then
          ensureBool "Kea advertisement ${toString advertisementIndex}.enabled for runtime target '${runtimeTargetName}'" advertisementDef.enabled
        else
          true;

      interfaceName = resolveInterfaceName runtimeTargetName advertisementIndex advertisementDef;

      subnet =
        if advertisementDef ? subnet then
          ensureString "Kea advertisement ${toString advertisementIndex}.subnet for runtime target '${runtimeTargetName}'" advertisementDef.subnet
        else
          throw ''
            network-renderer-nixos: Kea advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}' is missing subnet
            advertisement=${safeJson advertisementDef}
          '';

      pools =
        if advertisementDef ? pools then
          map
            (
              pool:
              normalizePoolRange "Kea advertisement ${toString advertisementIndex}.pools entry for runtime target '${runtimeTargetName}'" pool
            )
            (
              ensureList "Kea advertisement ${toString advertisementIndex}.pools for runtime target '${runtimeTargetName}'" advertisementDef.pools
            )
        else if advertisementDef ? pool then
          [
            (normalizePoolRange "Kea advertisement ${toString advertisementIndex}.pool for runtime target '${runtimeTargetName}'" advertisementDef.pool)
          ]
        else
          throw ''
            network-renderer-nixos: Kea advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}' is missing pool/pools
            advertisement=${safeJson advertisementDef}
          '';

      routers =
        normalizeOptionalAddressList
          "Kea advertisement ${toString advertisementIndex}.routers for runtime target '${runtimeTargetName}'"
          (
            if advertisementDef ? routers then
              advertisementDef.routers
            else if advertisementDef ? router then
              advertisementDef.router
            else
              null
          );

      dnsServers =
        normalizeOptionalAddressList
          "Kea advertisement ${toString advertisementIndex}.dnsServers for runtime target '${runtimeTargetName}'"
          (
            if advertisementDef ? dnsServers then
              advertisementDef.dnsServers
            else if advertisementDef ? nameServers then
              advertisementDef.nameServers
            else
              null
          );

      domain =
        normalizeOptionalString
          "Kea advertisement ${toString advertisementIndex}.domain for runtime target '${runtimeTargetName}'"
          (
            if advertisementDef ? domain then
              advertisementDef.domain
            else if advertisementDef ? domainName then
              advertisementDef.domainName
            else
              null
          );

      advertisementId =
        normalizeOptionalString
          "Kea advertisement ${toString advertisementIndex}.id for runtime target '${runtimeTargetName}'"
          (advertisementDef.id or null);

      tenant =
        normalizeOptionalString
          "Kea advertisement ${toString advertisementIndex}.tenant for runtime target '${runtimeTargetName}'"
          (advertisementDef.tenant or null);

      subnetId =
        normalizeOptionalInt
          "Kea advertisement ${toString advertisementIndex}.subnetId for runtime target '${runtimeTargetName}'"
          (if advertisementDef ? subnetId then advertisementDef.subnetId else null);

      routerInterface =
        normalizeOptionalRouterInterface
          "Kea advertisement ${toString advertisementIndex}.routerInterface for runtime target '${runtimeTargetName}'"
          (advertisementDef.routerInterface or null);

      routerInterfaceAddress =
        normalizeOptionalString
          "Kea advertisement ${toString advertisementIndex}.routerInterfaceAddress for runtime target '${runtimeTargetName}'"
          (advertisementDef.routerInterfaceAddress or null);

      normalizedAdvertisement = compactAttrs {
        inherit
          advertisementId
          interfaceName
          subnet
          subnetId
          pools
          routers
          dnsServers
          domain
          tenant
          routerInterface
          routerInterfaceAddress
          ;
      };

      _enabled =
        if enabled then
          true
        else
          throw ''
            network-renderer-nixos: Kea advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}' was selected despite enabled = false
            advertisement=${safeJson advertisementDef}
          '';

      _jsonable =
        ensureJsonableWithSource
          "Kea advertisement ${toString advertisementIndex} normalized model for runtime target '${runtimeTargetName}'"
          normalizedAdvertisement
          advertisementDef;
    in
    builtins.seq _enabled (builtins.seq _jsonable normalizedAdvertisement)
  ) (lib.range 0 ((builtins.length advertisementList) - 1));

  _haveAdvertisements =
    if normalizedAdvertisements == [ ] then
      throw ''
        network-renderer-nixos: Kea runtime target service model requires at least one advertisement
        advertisements=${safeJson advertisements}
        artifactContext=${safeJson context}
      ''
    else
      true;

  serviceModel = {
    service = "kea";
    inherit
      enterprise
      site
      host
      container
      runtimeTargetName
      runtimeTargetArtifactPath
      ;
    scopes = normalizedAdvertisements;
  };

  _serviceModelJsonable =
    ensureJsonableWithSource
      "Kea runtime target service model for runtime target '${runtimeTargetName}'"
      serviceModel
      {
        inherit context advertisements;
      };
in
builtins.seq _haveAdvertisements (builtins.seq _serviceModelJsonable serviceModel)
