{
  communicationContract,
  ownership,
  inventory,
  common,
}:

let
  toNamedAttrs =
    values:
    builtins.listToAttrs (
      map (entry: {
        name = entry.name;
        value = entry;
      }) (builtins.filter (entry: builtins.isAttrs entry && builtins.isString (entry.name or null)) values)
    );
in
{
  trafficTypeDefinitions =
    if communicationContract ? trafficTypes && builtins.isList communicationContract.trafficTypes then
      toNamedAttrs communicationContract.trafficTypes
    else
      { };

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      toNamedAttrs communicationContract.services
    else
      { };

  ownershipEndpoints =
    if ownership ? endpoints && builtins.isList ownership.endpoints then
      toNamedAttrs ownership.endpoints
    else
      { };

  inventoryEndpoints =
    if inventory ? endpoints && builtins.isAttrs inventory.endpoints then inventory.endpoints else { };

  allowRelations =
    if communicationContract ? relations && builtins.isList communicationContract.relations then
      builtins.filter builtins.isAttrs communicationContract.relations
    else
      [ ];
}
