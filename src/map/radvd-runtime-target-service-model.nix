{ lib }:
{
  artifactContext,
  advertisements,
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

  ensureInt =
    name: value:
    if builtins.isInt value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an integer";

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

  compactAttrs = attrs: lib.filterAttrs (_: value: value != null) attrs;

  normalizeOptionalString = name: value: if value == null then null else ensureString name value;

  normalizeOptionalInt = name: value: if value == null then null else ensureInt name value;

  normalizeOptionalBool = name: value: if value == null then null else ensureBool name value;

  normalizeOptionalStringList =
    name: value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [
        ensureString
        name
        value
      ]
    else
      map (entry: ensureString "${name} entry" entry) (ensureList name value);

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

  normalizePrefix =
    name: value:
    if builtins.isString value then
      {
        prefix = ensureString name value;
      }
    else
      let
        prefixDef = ensureAttrs name value;
      in
      compactAttrs {
        prefix =
          if prefixDef ? prefix then
            ensureString "${name}.prefix" prefixDef.prefix
          else if prefixDef ? cidr then
            ensureString "${name}.cidr" prefixDef.cidr
          else
            throw "network-renderer-nixos: ${name} is missing prefix/cidr";
        advOnLink = normalizeOptionalBool "${name}.advOnLink" (prefixDef.advOnLink or null);
        advAutonomous = normalizeOptionalBool "${name}.advAutonomous" (prefixDef.advAutonomous or null);
      };

  resolveInterfaceName =
    runtimeTargetName: advertisementIndex: advertisement:
    let
      advertisementDef = ensureAttrs "radvd advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}'" advertisement;

      routerInterface =
        if advertisementDef ? routerInterface then
          ensureAttrs "radvd advertisement ${toString advertisementIndex} routerInterface for runtime target '${runtimeTargetName}'" advertisementDef.routerInterface
        else
          { };
    in
    if advertisementDef ? bindInterface then
      ensureString "radvd advertisement ${toString advertisementIndex}.bindInterface for runtime target '${runtimeTargetName}'" advertisementDef.bindInterface
    else if advertisementDef ? interface then
      ensureString "radvd advertisement ${toString advertisementIndex}.interface for runtime target '${runtimeTargetName}'" advertisementDef.interface
    else if routerInterface ? bindInterface then
      ensureString "radvd advertisement ${toString advertisementIndex}.routerInterface.bindInterface for runtime target '${runtimeTargetName}'" routerInterface.bindInterface
    else if routerInterface ? interface then
      ensureString "radvd advertisement ${toString advertisementIndex}.routerInterface.interface for runtime target '${runtimeTargetName}'" routerInterface.interface
    else
      throw "network-renderer-nixos: radvd advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}' is missing bindInterface/interface";

  context = ensureAttrs "artifactContext" artifactContext;

  enterprise = ensureString "artifactContext.enterpriseName" context.enterpriseName;
  site = ensureString "artifactContext.siteName" context.siteName;
  host = ensureString "artifactContext.hostName" context.hostName;
  container = ensureString "artifactContext.containerName" context.containerName;
  runtimeTargetName = ensureString "artifactContext.runtimeTargetName" context.runtimeTargetName;
  runtimeTargetArtifactPath = ensureString "artifactContext.runtimeTargetArtifactPath" context.runtimeTargetArtifactPath;

  normalizedAdvertisements = map (
    advertisementIndex:
    let
      advertisement = builtins.elemAt (ensureList "radvd advertisements" advertisements) advertisementIndex;

      advertisementDef = ensureAttrs "radvd advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}'" advertisement;

      enabled =
        if advertisementDef ? enabled then
          ensureBool "radvd advertisement ${toString advertisementIndex}.enabled for runtime target '${runtimeTargetName}'" advertisementDef.enabled
        else
          true;

      interfaceName = resolveInterfaceName runtimeTargetName advertisementIndex advertisementDef;

      prefixes =
        if advertisementDef ? prefixes then
          map
            (
              prefix:
              normalizePrefix "radvd advertisement ${toString advertisementIndex}.prefixes entry for runtime target '${runtimeTargetName}'" prefix
            )
            (
              ensureList "radvd advertisement ${toString advertisementIndex}.prefixes for runtime target '${runtimeTargetName}'" advertisementDef.prefixes
            )
        else if advertisementDef ? prefix then
          [
            (normalizePrefix "radvd advertisement ${toString advertisementIndex}.prefix for runtime target '${runtimeTargetName}'" advertisementDef.prefix)
          ]
        else
          throw "network-renderer-nixos: radvd advertisement ${toString advertisementIndex} for runtime target '${runtimeTargetName}' is missing prefix/prefixes";

      rdnss =
        normalizeOptionalStringList
          "radvd advertisement ${toString advertisementIndex}.rdnss for runtime target '${runtimeTargetName}'"
          (
            if advertisementDef ? rdnss then
              advertisementDef.rdnss
            else if advertisementDef ? dnsServers then
              advertisementDef.dnsServers
            else
              null
          );

      dnssl =
        normalizeOptionalStringList
          "radvd advertisement ${toString advertisementIndex}.dnssl for runtime target '${runtimeTargetName}'"
          (
            if advertisementDef ? dnssl then
              advertisementDef.dnssl
            else if advertisementDef ? domain then
              advertisementDef.domain
            else if advertisementDef ? domainName then
              advertisementDef.domainName
            else
              null
          );

      advertisementId =
        normalizeOptionalString
          "radvd advertisement ${toString advertisementIndex}.id for runtime target '${runtimeTargetName}'"
          (advertisementDef.id or null);

      tenant =
        normalizeOptionalString
          "radvd advertisement ${toString advertisementIndex}.tenant for runtime target '${runtimeTargetName}'"
          (advertisementDef.tenant or null);

      advManagedFlag =
        normalizeOptionalBool
          "radvd advertisement ${toString advertisementIndex}.advManagedFlag for runtime target '${runtimeTargetName}'"
          (advertisementDef.advManagedFlag or null);

      advOtherConfigFlag =
        normalizeOptionalBool
          "radvd advertisement ${toString advertisementIndex}.advOtherConfigFlag for runtime target '${runtimeTargetName}'"
          (advertisementDef.advOtherConfigFlag or null);

      minRtrAdvInterval =
        normalizeOptionalInt
          "radvd advertisement ${toString advertisementIndex}.minRtrAdvInterval for runtime target '${runtimeTargetName}'"
          (advertisementDef.minRtrAdvInterval or null);

      maxRtrAdvInterval =
        normalizeOptionalInt
          "radvd advertisement ${toString advertisementIndex}.maxRtrAdvInterval for runtime target '${runtimeTargetName}'"
          (advertisementDef.maxRtrAdvInterval or null);

      routerInterface =
        normalizeOptionalRouterInterface
          "radvd advertisement ${toString advertisementIndex}.routerInterface for runtime target '${runtimeTargetName}'"
          (advertisementDef.routerInterface or null);

      routerInterfaceAddress =
        normalizeOptionalString
          "radvd advertisement ${toString advertisementIndex}.routerInterfaceAddress for runtime target '${runtimeTargetName}'"
          (advertisementDef.routerInterfaceAddress or null);
    in
    compactAttrs {
      inherit
        advertisementId
        interfaceName
        prefixes
        rdnss
        dnssl
        tenant
        advManagedFlag
        advOtherConfigFlag
        minRtrAdvInterval
        maxRtrAdvInterval
        routerInterface
        routerInterfaceAddress
        ;
    }
  ) (lib.range 0 ((builtins.length (ensureList "radvd advertisements" advertisements)) - 1));

  _haveAdvertisements =
    if normalizedAdvertisements == [ ] then
      throw "network-renderer-nixos: radvd runtime target service model requires at least one advertisement"
    else
      true;
in
builtins.seq _haveAdvertisements {
  service = "radvd";
  inherit
    enterprise
    site
    host
    container
    runtimeTargetName
    runtimeTargetArtifactPath
    ;
  advertisements = normalizedAdvertisements;
}
