{
  lib,
  communicationContract,
  ownership,
  tenantInterfaceByName,
  common,
}:

let
  inherit (common) sortedStrings;

  ownershipEndpoints =
    if ownership ? endpoints && builtins.isList ownership.endpoints then
      lib.filter (
        endpoint:
        builtins.isAttrs endpoint
        && endpoint ? name
        && builtins.isString endpoint.name
        && endpoint ? tenant
        && builtins.isString endpoint.tenant
      ) ownership.endpoints
    else
      [ ];

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      lib.filter (
        service: builtins.isAttrs service && service ? name && builtins.isString service.name
      ) communicationContract.services
    else
      [ ];

  providerTenantFor =
    providerName:
    let
      matches = lib.filter (endpoint: endpoint.name == providerName) ownershipEndpoints;
    in
    if builtins.length matches > 0 then (builtins.head matches).tenant else null;
in
{
  serviceInterfacesByName = builtins.listToAttrs (
    map (
      service:
      let
        providers =
          if service ? providers && builtins.isList service.providers then
            lib.filter builtins.isString service.providers
          else
            [ ];

        providerTenants =
          if service ? providerTenants && builtins.isList service.providerTenants then
            lib.filter builtins.isString service.providerTenants
          else
            lib.filter (tenant: tenant != null) (map providerTenantFor providers);

        interfaces = sortedStrings (
          lib.filter (iface: iface != null) (
            map (
              tenant:
              if builtins.hasAttr tenant tenantInterfaceByName then tenantInterfaceByName.${tenant} else null
            ) providerTenants
          )
        );
      in
      {
        name = service.name;
        value = interfaces;
      }
    ) serviceDefinitions
  );
}
