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

  enabledList =
    name:
    let
      raw =
        if builtins.hasAttr name cpmAdvertisements && builtins.isList cpmAdvertisements.${name} then
          cpmAdvertisements.${name}
        else
          [ ];
    in
    lib.filter (
      entry:
      builtins.isAttrs entry
      &&
        (entry.enabled
          or (throw "FS-310-HDS-030-SDS-010-SMS-111: entry.enabled required by CPM provider contract, cannot default to true")
        ) != false
    ) raw;

  authoritativeDhcp4 = enabledList "dhcp4";
  authoritativeDhcpv6 = enabledList "dhcpv6";
  authoritativeIpv6Ra = enabledList "ipv6Ra";

  stateContracts = import ./state-contracts.nix {
    inherit lib runtimeTarget;
  };

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
    else if
      builtins.isAttrs pool
      && builtins.isString (pool.start or null)
      && builtins.isString (pool.end or null)
    then
      "${pool.start} - ${pool.end}"
    else
      null;

  requireBool =
    path: value:
    if builtins.isBool value then
      value
    else
      throw "CPM renderer contract update required: ${path} must be an explicit boolean";

  requireNonEmptyString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "CPM renderer contract update required: ${path} must be a non-empty string";

  forbiddenReservationAuthorityKeys = [
    "reachability"
    "routes"
    "route"
    "policyRoutes"
    "firewall"
    "dnsRecursion"
    "recursiveDns"
    "managementAccess"
    "publicEgress"
    "egress"
    "nat"
  ];

  rejectReservationAuthority =
    path: reservation:
    let
      present = lib.filter (name: builtins.hasAttr name reservation) forbiddenReservationAuthorityKeys;
    in
    if present == [ ] then
      true
    else
      throw "CPM renderer contract update required: ${path} must not carry unrelated network authority fields: ${lib.concatStringsSep ", " present}";

  reservationRuntimeSourceFile =
    reservation:
    if
      builtins.isAttrs (reservation.identitySource or null)
      && builtins.isString (reservation.identitySource.sourceFile or null)
      && reservation.identitySource.sourceFile != ""
    then
      reservation.identitySource.sourceFile
    else
      null;

  reservationSourceFor =
    family: entryPath: adv:
    let
      raw = adv.reservationSource or null;
    in
    if raw == null then
      null
    else if !builtins.isAttrs raw then
      throw "CPM renderer contract update required: ${entryPath}.reservationSource must be an opaque protected-source record"
    else
      let
        schema = requireNonEmptyString "${entryPath}.reservationSource.schema" (raw.schema or null);
        sourceClass = requireNonEmptyString "${entryPath}.reservationSource.sourceClass" (
          raw.sourceClass or null
        );
        sourceFile = requireNonEmptyString "${entryPath}.reservationSource.sourceFile" (
          raw.sourceFile or null
        );
        rawReservations = if builtins.isList (adv.reservations or null) then adv.reservations else [ ];
        _schema =
          if schema == "gamp-protected-reservation-set-v1" then
            true
          else
            throw "CPM renderer contract update required: ${entryPath}.reservationSource.schema must be gamp-protected-reservation-set-v1";
        _protected =
          if sourceClass == "protected" then
            true
          else
            throw "diagnostic.protected-reservation-identity-leaked: ${entryPath}.reservationSource must remain protected";
        _sourcePath =
          if lib.hasPrefix "/run/secrets/" sourceFile then
            true
          else
            throw "diagnostic.runtime-reservation-source-path-invalid: ${entryPath}.reservationSource.sourceFile must be delivered from the renderer-approved /run/secrets/ runtime secret boundary";
        _scopeOnly =
          if rawReservations == [ ] then
            true
          else
            throw "diagnostic.runtime-reservation-source-conflict: ${entryPath} must not combine one protected reservationSource with public per-reservation descriptors";
        _servedScope = builtins.seq (requireNonEmptyString "${entryPath}.subnet" (adv.subnet or null)) true;
      in
      builtins.seq _schema (
        builtins.seq _protected (
          builtins.seq _sourcePath (
            builtins.seq _scopeOnly (
              builtins.seq _servedScope {
                inherit schema sourceClass sourceFile;
                inherit family;
              }
            )
          )
        )
      );

  validateReservationAddressFamily =
    path: family: address:
    if family == "dhcp4" && builtins.match ".*:.*" address != null then
      throw "CPM renderer contract update required: ${path}.address must be a resolved IPv4 reservation address"
    else if family == "dhcpv6" && builtins.match ".*:.*" address == null then
      throw "CPM renderer contract update required: ${path}.address must be a resolved IPv6 reservation address"
    else
      true;

  validateReservation =
    family: path: reservation:
    if !builtins.isAttrs reservation then
      throw "CPM renderer contract update required: ${path} must be a reservation record"
    else
      let
        address = requireNonEmptyString "${path}.address" (reservation.address or null);
        runtimeSourceFile = reservationRuntimeSourceFile reservation;
        _runtimeSourceFileBoundary =
          if runtimeSourceFile == null then
            true
          else
            throw "diagnostic.runtime-reservation-source-must-be-scope-level: ${path}.identitySource.sourceFile is a public per-reservation descriptor; protected runtime recordsets belong on the served advertisement reservationSource";
        _family = validateReservationAddressFamily path family address;
        _identity =
          if family == "dhcpv6" then
            if
              (builtins.isString (reservation.mac or null) && reservation.mac != "")
              || (builtins.isString (reservation.duid or null) && reservation.duid != "")
            then
              true
            else
              throw "CPM renderer contract update required: ${path} must carry explicit mac or duid identity"
          else if builtins.isString (reservation.mac or null) && reservation.mac != "" then
            true
          else if runtimeSourceFile != null then
            true
          else
            throw "CPM renderer contract update required: ${path} must carry explicit mac or identitySource.sourceFile";
        _authority = rejectReservationAuthority path reservation;
      in
      builtins.seq _runtimeSourceFileBoundary (
        builtins.seq _family (builtins.seq _identity (builtins.seq _authority reservation))
      );

  reservationsFor =
    family: entryPath: adv:
    let
      raw =
        if builtins.hasAttr "reservations" adv then
          if builtins.isList adv.reservations then
            adv.reservations
          else
            throw "CPM renderer contract update required: ${entryPath}.reservations must be a list"
        else
          [ ];
      _servedScope =
        if raw == [ ] then
          true
        else
          builtins.seq (requireNonEmptyString "${entryPath}.subnet" (adv.subnet or null)) true;
    in
    builtins.seq _servedScope (
      builtins.genList (
        idx:
        validateReservation family "${entryPath}.reservations[${builtins.toString idx}]" (
          builtins.elemAt raw idx
        )
      ) (builtins.length raw)
    );

  delegatedPrefixFor =
    { adv, tenantName }:
    let
      cpmRoutedPrefix =
        if builtins.isAttrs (adv.delegatedPrefix or null) then adv.delegatedPrefix else null;
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
        uplink =
          if builtins.isString (cpmRoutedPrefix.uplink or null) && cpmRoutedPrefix.uplink != "" then
            cpmRoutedPrefix.uplink
          else
            throw "FS-310-HDS-010-SDS-010-SMS-110: CPM must provide uplink name in advertisements.ipv6Ra[].delegatedPrefix.uplink, cannot default to 'routed-prefix'";
        delegatedPrefixLength =
          cpmRoutedPrefix.delegatedPrefixLength
            or (throw "FS-310-HDS-030-SDS-010-SMS-111: cpmRoutedPrefix.delegatedPrefixLength required by CPM provider contract, cannot default to 64");
        perTenantPrefixLength =
          cpmRoutedPrefix.perTenantPrefixLength
            or (throw "FS-310-HDS-030-SDS-010-SMS-111: cpmRoutedPrefix.perTenantPrefixLength required by CPM provider contract, cannot default to 64");
        slot =
          cpmRoutedPrefix.slot
            or (throw "FS-310-HDS-030-SDS-010-SMS-111: cpmRoutedPrefix.slot required by CPM provider contract, cannot default to 0");
        sourceFile = cpmRoutedPrefix.sourceFile or null;
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
  haveAuthoritativeAdvertisements =
    authoritativeDhcp4 != [ ] || authoritativeDhcpv6 != [ ] || authoritativeIpv6Ra != [ ];

  authoritativeDhcp4Scopes = builtins.genList (
    idx:
    let
      adv = builtins.elemAt authoritativeDhcp4 idx;
      entryPath = "runtimeTarget.advertisements.dhcp4[${builtins.toString idx}]";
      interfaceName = advInterface adv;
      stem = safeStem (
        if builtins.isString (adv.id or null) && adv.id != "" then
          adv.id
        else if interfaceName != null then
          interfaceName
        else
          "dhcp4-${builtins.toString (idx + 1)}"
      );
      leaseState = stateContracts.contractFor {
        listName = "dhcp4Leases";
        service = "dhcp4";
        inherit adv interfaceName idx;
      };
      router =
        if builtins.isString (adv.router or null) && adv.router != "" then
          adv.router
        else if builtins.isString (adv.routerAddress or null) && adv.routerAddress != "" then
          adv.routerAddress
        else
          null;
      reservationSource = reservationSourceFor "ipv4" entryPath adv;
    in
    {
      serviceName = "lan-${stem}";
      fileStem = stem;
      interfaceKey = interfaceName;
      inherit leaseState;
      inherit interfaceName router;
      scopeId = requireNonEmptyString "${entryPath}.id" (adv.id or null);
      subnet = if builtins.isString (adv.subnet or null) && adv.subnet != "" then adv.subnet else null;
      pool = poolStringFrom (adv.pool or null);
      reservations = reservationsFor "dhcp4" entryPath adv;
      dnsServers = if adv ? dnsServers then asStringList adv.dnsServers else [ ];
      domain =
        if builtins.isString (adv.domain or null) && adv.domain != "" then
          adv.domain
        else
          throw "FS-310-HDS-010-SDS-010-SMS-110: CPM must provide DHCP domain in advertisements.dhcp4[].domain, cannot default to 'lan.'";
      subnetId = idx + 1;
    }
    // lib.optionalAttrs (reservationSource != null) { inherit reservationSource; }
  ) (builtins.length authoritativeDhcp4);

  authoritativeDhcpv6Scopes = builtins.genList (
    idx:
    let
      adv = builtins.elemAt authoritativeDhcpv6 idx;
      entryPath = "runtimeTarget.advertisements.dhcpv6[${builtins.toString idx}]";
      interfaceName = advInterface adv;
      stem = safeStem (
        if builtins.isString (adv.id or null) && adv.id != "" then
          adv.id
        else if interfaceName != null then
          interfaceName
        else
          "dhcpv6-${builtins.toString (idx + 1)}"
      );
      leaseState = stateContracts.contractFor {
        listName = "dhcpv6Leases";
        service = "dhcpv6";
        inherit adv interfaceName idx;
      };
      reservationSource = reservationSourceFor "ipv6" entryPath adv;
    in
    {
      serviceName = "lan-${stem}";
      fileStem = stem;
      interfaceKey = interfaceName;
      inherit leaseState;
      inherit interfaceName;
      scopeId = requireNonEmptyString "${entryPath}.id" (adv.id or null);
      subnet = if builtins.isString (adv.subnet or null) && adv.subnet != "" then adv.subnet else null;
      pool = poolStringFrom (adv.pool or null);
      reservations = reservationsFor "dhcpv6" entryPath adv;
      dnsServers = if adv ? dnsServers then asStringList adv.dnsServers else [ ];
      domain =
        if builtins.isString (adv.domain or null) && adv.domain != "" then
          adv.domain
        else
          throw "FS-310-HDS-010-SDS-010-SMS-110: CPM must provide DHCP domain in advertisements.dhcpv6[].domain, cannot default to 'lan.'";
      subnetId = idx + 1;
    }
    // lib.optionalAttrs (reservationSource != null) { inherit reservationSource; }
  ) (builtins.length authoritativeDhcpv6);

  authoritativeRadvdScopes = builtins.genList (
    idx:
    let
      adv = builtins.elemAt authoritativeIpv6Ra idx;
      interfaceName = advInterface adv;
      stem = safeStem (
        if interfaceName != null then interfaceName else "radvd-${builtins.toString (idx + 1)}"
      );
      tenantName =
        if builtins.isString (adv.tenant or null) && adv.tenant != "" then adv.tenant else null;
      delegatedPrefix = delegatedPrefixFor { inherit adv tenantName; };
      dnssl = if adv ? dnssl then asStringList adv.dnssl else [ ];
    in
    {
      serviceName = "lan-${stem}";
      fileStem = stem;
      interfaceKey = interfaceName;
      inherit interfaceName;
      prefixes = if adv ? prefixes then asStringList adv.prefixes else [ ];
      rdnss = if adv ? rdnss then asStringList adv.rdnss else [ ];
      domain =
        if dnssl != [ ] then
          builtins.head dnssl
        else
          throw "FS-310-HDS-010-SDS-010-SMS-110: CPM must provide DHCP domain in advertisements.ipv6Ra[].dnssl, cannot default to 'lan.'";
      managed = requireBool "runtimeTarget.advertisements.ipv6Ra[${builtins.toString idx}].managed" (
        adv.managed or null
      );
      otherConfig =
        requireBool "runtimeTarget.advertisements.ipv6Ra[${builtins.toString idx}].otherConfig"
          (adv.otherConfig or null);
      onLink = requireBool "runtimeTarget.advertisements.ipv6Ra[${builtins.toString idx}].onLink" (
        adv.onLink or null
      );
      autonomous =
        requireBool "runtimeTarget.advertisements.ipv6Ra[${builtins.toString idx}].autonomous"
          (adv.autonomous or null);
    }
    // lib.optionalAttrs (delegatedPrefix != null) { inherit delegatedPrefix; }
  ) (builtins.length authoritativeIpv6Ra);
}
