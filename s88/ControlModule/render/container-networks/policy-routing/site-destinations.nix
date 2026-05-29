{ lib, containerModel, common }:

let
  inherit (common) policyTenantKeyFor stringContains;

  siteTenants =
    if containerModel ? site && builtins.isAttrs containerModel.site then
      containerModel.site.tenants or (containerModel.site.domains.tenants or [ ])
    else
      [ ];

  transitAdjacencies =
    if
      containerModel ? site
      && builtins.isAttrs containerModel.site
      && containerModel.site ? transit
      && builtins.isAttrs containerModel.site.transit
      && builtins.isList (containerModel.site.transit.adjacencies or null)
    then
      containerModel.site.transit.adjacencies
    else
      [ ];

  runtimeTargets =
    if
      containerModel ? site
      && builtins.isAttrs containerModel.site
      && builtins.isAttrs (containerModel.site.runtimeTargets or null)
    then
      containerModel.site.runtimeTargets
    else
      { };

  tenantPrefixOwners =
    if
      containerModel ? site
      && builtins.isAttrs containerModel.site
      && builtins.isAttrs (containerModel.site.tenantPrefixOwners or null)
    then
      containerModel.site.tenantPrefixOwners
    else
      { };

  tenantPrefixesFor =
    tenantKey:
    lib.concatMap
      (
        tenant:
        if policyTenantKeyFor "down-${tenant.name or ""}" != tenantKey then
          [ ]
        else
          (lib.optional (builtins.isString (tenant.ipv4 or null)) tenant.ipv4)
          ++ (lib.optional (builtins.isString (tenant.ipv6 or null)) tenant.ipv6)
      )
      siteTenants;

  tenantPrefixesForAccessUnit =
    accessUnit:
    lib.concatMap
      (
        owner:
        if (owner.owner or null) == accessUnit && builtins.isString (owner.dst or null) then
          [ owner.dst ]
        else
          [ ]
      )
      (builtins.attrValues tenantPrefixOwners);

  accessTransitPrefixesFor =
    tenantKey:
    lib.concatMap
      (
        adjacency:
        lib.concatMap
          (
            endpoint:
            let
              unit = endpoint.unit or "";
              local = endpoint.local or { };
            in
            if !(builtins.isString unit) || !(stringContains "-access-${tenantKey}" unit) then
              [ ]
            else
              (lib.optional (builtins.isString (local.ipv4 or null)) "${local.ipv4}/31")
              ++ (lib.optional (builtins.isString (local.ipv6 or null)) "${local.ipv6}/127")
          )
          (adjacency.endpoints or [ ])
      )
      transitAdjacencies;

  accessTransitPrefixesForAccessUnit =
    accessUnit:
    lib.concatMap
      (
        adjacency:
        lib.concatMap
          (
            endpoint:
            let
              unit = endpoint.unit or "";
              local = endpoint.local or { };
            in
            if unit != accessUnit then
              [ ]
            else
              (lib.optional (builtins.isString (local.ipv4 or null)) "${local.ipv4}/31")
              ++ (lib.optional (builtins.isString (local.ipv6 or null)) "${local.ipv6}/127")
          )
          (adjacency.endpoints or [ ])
      )
      transitAdjacencies;

  dnsAllowFromPrefixesFor =
    tenantKey:
    lib.concatMap
      (
        targetName:
        let
          target = runtimeTargets.${targetName};
          services = target.services or { };
          dns = services.dns or { };
        in
        if !(stringContains "-access-${tenantKey}" targetName) then
          [ ]
        else if builtins.isList (dns.allowFrom or null) then
          lib.filter builtins.isString dns.allowFrom
        else
          [ ]
      )
      (builtins.attrNames runtimeTargets);

  dnsAllowFromPrefixesForAccessUnit =
    accessUnit:
    lib.concatMap
      (
        targetName:
        let
          target = runtimeTargets.${targetName};
          services = target.services or { };
          dns = services.dns or { };
        in
        if targetName != accessUnit then
          [ ]
        else if builtins.isList (dns.allowFrom or null) then
          lib.filter builtins.isString dns.allowFrom
        else
          [ ]
      )
      (builtins.attrNames runtimeTargets);

  dnsAllowFromTransitPrefixesFor =
    tenantKey:
    lib.filter
      (
        prefix:
        (builtins.isString prefix)
        && ((lib.hasSuffix "/31" prefix) || (lib.hasSuffix "/127" prefix))
      )
      (dnsAllowFromPrefixesFor tenantKey);

  dnsAllowFromTransitPrefixesForAccessUnit =
    accessUnit:
    lib.filter
      (
        prefix:
        (builtins.isString prefix)
        && ((lib.hasSuffix "/31" prefix) || (lib.hasSuffix "/127" prefix))
      )
      (dnsAllowFromPrefixesForAccessUnit accessUnit);
in
{
  returnDestinationsForAccessUnit =
    accessUnit:
    lib.unique (
      (tenantPrefixesForAccessUnit accessUnit ++ accessTransitPrefixesForAccessUnit accessUnit)
      ++ dnsAllowFromTransitPrefixesForAccessUnit accessUnit
    );

  returnDestinationsForTenant =
    tenantKey:
    lib.unique (
      (tenantPrefixesFor tenantKey ++ accessTransitPrefixesFor tenantKey)
      ++ dnsAllowFromTransitPrefixesFor tenantKey
    );

  destinationsForTenant =
    tenantKey:
    lib.unique ((tenantPrefixesFor tenantKey ++ accessTransitPrefixesFor tenantKey) ++ dnsAllowFromPrefixesFor tenantKey);
}
