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

  tenantPrefixesFor =
    tenantKey:
    lib.concatMap (
      tenant:
      if policyTenantKeyFor "down-${tenant.name or ""}" != tenantKey then
        [ ]
      else
        (lib.optional (builtins.isString (tenant.ipv4 or null)) tenant.ipv4)
        ++ (lib.optional (builtins.isString (tenant.ipv6 or null)) tenant.ipv6)
    ) siteTenants;

  accessTransitPrefixesFor =
    tenantKey:
    lib.concatMap (
      adjacency:
      lib.concatMap (
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
      ) (adjacency.endpoints or [ ])
    ) transitAdjacencies;

  dnsAllowFromPrefixesFor =
    tenantKey:
    lib.concatMap (
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
    ) (builtins.attrNames runtimeTargets);
in
{
  destinationsForTenant =
    tenantKey:
    lib.unique (
      tenantPrefixesFor tenantKey
      ++ accessTransitPrefixesFor tenantKey
      ++ dnsAllowFromPrefixesFor tenantKey
    );
}
