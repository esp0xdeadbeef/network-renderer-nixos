{
  lib,
}:
communicationContract:
let
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

  json = value: builtins.toJSON value;

  contract = ensureAttrs "communicationContract" communicationContract;

  relations =
    if contract ? relations then
      ensureList "communicationContract.relations" contract.relations
    else if contract ? allowedRelations then
      ensureList "communicationContract.allowedRelations" contract.allowedRelations
    else
      throw ''
        network-renderer-nixos: communicationContract is missing relations
        communicationContract=${json contract}
      '';

  trafficTypes =
    if contract ? trafficTypes then
      ensureList "communicationContract.trafficTypes" contract.trafficTypes
    else
      throw ''
        network-renderer-nixos: communicationContract is missing trafficTypes
        communicationContract=${json contract}
      '';

  services =
    if contract ? services then
      ensureList "communicationContract.services" contract.services
    else
      throw ''
        network-renderer-nixos: communicationContract is missing services
        communicationContract=${json contract}
      '';
in
contract
// {
  inherit
    relations
    trafficTypes
    services
    ;
}
