{
  lib,
  runtimeTarget,
  currentSiteIpv6,
  currentInventorySiteIpv6,
  resolveAuthoritativeInterfaceName,
  common,
}:

let
  inherit (common) asStringList safeStem;

  cpmAdvertisements =
    if runtimeTarget ? advertisements && builtins.isAttrs runtimeTarget.advertisements then
      runtimeTarget.advertisements
    else
      { };

  cpmExternalValidation =
    if runtimeTarget ? externalValidation && builtins.isAttrs runtimeTarget.externalValidation then
      runtimeTarget.externalValidation
    else
      { };

  enabledList =
    name:
    let
      raw =
        if builtins.hasAttr name cpmAdvertisements && builtins.isList cpmAdvertisements.${name} then
          cpmAdvertisements.${name}
        else
          [ ];
    in
    lib.filter (entry: builtins.isAttrs entry && (entry.enabled or true) != false) raw;

  authoritativeDhcp4 = enabledList "dhcp4";
  authoritativeIpv6Ra = enabledList "ipv6Ra";

  advInterface =
    adv:
    resolveAuthoritativeInterfaceName (
      if builtins.isString (adv.interface or null) && adv.interface != "" then
        adv.interface
      else if builtins.isString (adv.bindInterface or null) && adv.bindInterface != "" then
        adv.bindInterface
      else
        null
    );

  poolStringFrom =
    pool:
    if builtins.isString pool then
      pool
    else if builtins.isAttrs pool && builtins.isString (pool.start or null) && builtins.isString (pool.end or null) then
      "${pool.start} - ${pool.end}"
    else
      null;

  delegatedPrefixFor =
    { adv, tenantName }:
    let
      cpmRoutedPrefix =
        if builtins.isAttrs (adv.delegatedPrefix or null) then
          adv.delegatedPrefix
        else
          null;
      hasExternalValidationDelegatedPrefix =
        builtins.isString (cpmExternalValidation.delegatedPrefixSecretPath or null);
      tenantIpv6Plan =
        if
          tenantName != null
          && currentSiteIpv6 ? tenants
          && builtins.isAttrs currentSiteIpv6.tenants
          && builtins.hasAttr tenantName currentSiteIpv6.tenants
        then
          currentSiteIpv6.tenants.${tenantName}
        else
          { };
      configuredSourceFile =
        if builtins.isString (currentInventorySiteIpv6.pd.sourceFile or null) then
          currentInventorySiteIpv6.pd.sourceFile
        else
          null;
      uplinkName =
        if builtins.isString (currentSiteIpv6.pd.uplink or null) then currentSiteIpv6.pd.uplink else null;
    in
    if cpmRoutedPrefix != null then
      {
        uplink = cpmRoutedPrefix.uplink or "routed-prefix";
        delegatedPrefixLength = cpmRoutedPrefix.delegatedPrefixLength or 64;
        perTenantPrefixLength = cpmRoutedPrefix.perTenantPrefixLength or 64;
        slot = cpmRoutedPrefix.slot or 0;
        sourceFile = cpmRoutedPrefix.sourceFile or null;
      }
    else if hasExternalValidationDelegatedPrefix then
      {
        uplink = "external-validation";
        delegatedPrefixLength = 64;
        perTenantPrefixLength = 64;
        slot = 0;
        sourceFile = cpmExternalValidation.delegatedPrefixSecretPath;
      }
    else if
      tenantName != null
      && currentSiteIpv6 ? pd
      && builtins.isAttrs currentSiteIpv6.pd
      && tenantIpv6Plan ? pd
      && builtins.isAttrs tenantIpv6Plan.pd
      && builtins.isInt (tenantIpv6Plan.pd.slot or null)
    then
      {
        uplink = currentSiteIpv6.pd.uplink or null;
        delegatedPrefixLength = currentSiteIpv6.pd.delegatedPrefixLength or null;
        perTenantPrefixLength = currentSiteIpv6.pd.perTenantPrefixLength or null;
        slot = tenantIpv6Plan.pd.slot;
        sourceFile =
          if configuredSourceFile != null && configuredSourceFile != "" then
            configuredSourceFile
          else if uplinkName != null && uplinkName != "" then
            "/run/s88-ipv6-pd/${uplinkName}.prefix"
          else
            null;
      }
    else
      null;
in
{
  haveAuthoritativeAdvertisements = authoritativeDhcp4 != [ ] || authoritativeIpv6Ra != [ ];

  authoritativeDhcp4Scopes = builtins.genList (
    idx:
    let
      adv = builtins.elemAt authoritativeDhcp4 idx;
      interfaceName = advInterface adv;
      stem = safeStem (if builtins.isString (adv.id or null) && adv.id != "" then adv.id else if interfaceName != null then interfaceName else "dhcp4-${builtins.toString (idx + 1)}");
      router =
        if builtins.isString (adv.router or null) && adv.router != "" then
          adv.router
        else if builtins.isString (adv.routerAddress or null) && adv.routerAddress != "" then
          adv.routerAddress
        else
          null;
    in
    {
      serviceName = "lan-${stem}";
      fileStem = stem;
      interfaceKey = interfaceName;
      inherit interfaceName router;
      subnet = if builtins.isString (adv.subnet or null) && adv.subnet != "" then adv.subnet else null;
      pool = poolStringFrom (adv.pool or null);
      dnsServers = if adv ? dnsServers then asStringList adv.dnsServers else [ ];
      domain = if builtins.isString (adv.domain or null) && adv.domain != "" then adv.domain else "lan.";
      subnetId = idx + 1;
    }
  ) (builtins.length authoritativeDhcp4);

  authoritativeRadvdScopes = builtins.genList (
    idx:
    let
      adv = builtins.elemAt authoritativeIpv6Ra idx;
      interfaceName = advInterface adv;
      stem = safeStem (if interfaceName != null then interfaceName else "radvd-${builtins.toString (idx + 1)}");
      hasExternalValidationDelegatedPrefix = builtins.isString (cpmExternalValidation.delegatedPrefixSecretPath or null);
      hasRoutedDelegatedPrefix = builtins.isAttrs (adv.delegatedPrefix or null);
      tenantName = if builtins.isString (adv.tenant or null) && adv.tenant != "" then adv.tenant else null;
      delegatedPrefix = delegatedPrefixFor { inherit adv tenantName; };
      dnssl = if adv ? dnssl then asStringList adv.dnssl else [ ];
    in
    {
      serviceName = "lan-${stem}";
      fileStem = stem;
      interfaceKey = interfaceName;
      inherit interfaceName;
      prefixes =
        if hasExternalValidationDelegatedPrefix && !hasRoutedDelegatedPrefix then
          [ ]
        else if adv ? prefixes then
          asStringList adv.prefixes
        else
          [ ];
      rdnss = if adv ? rdnss then asStringList adv.rdnss else [ ];
      domain = if dnssl != [ ] then builtins.head dnssl else "lan.";
    }
    // lib.optionalAttrs (delegatedPrefix != null) { inherit delegatedPrefix; }
  ) (builtins.length authoritativeIpv6Ra);
}
