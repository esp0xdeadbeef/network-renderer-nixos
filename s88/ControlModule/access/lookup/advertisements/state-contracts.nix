{ lib, runtimeTarget }:

let
  persistenceContracts =
    if
      runtimeTarget ? stateContracts
      && builtins.isAttrs runtimeTarget.stateContracts
      && runtimeTarget.stateContracts ? persistence
      && builtins.isAttrs runtimeTarget.stateContracts.persistence
    then
      runtimeTarget.stateContracts.persistence
    else
      { };

  listFor =
    name:
    if builtins.hasAttr name persistenceContracts && builtins.isList persistenceContracts.${name} then
      lib.filter builtins.isAttrs persistenceContracts.${name}
    else
      [ ];

  rawInterfaceFor =
    adv:
    if builtins.isString (adv.interface or null) && adv.interface != "" then
      adv.interface
    else if builtins.isString (adv.bindInterface or null) && adv.bindInterface != "" then
      adv.bindInterface
    else
      null;

  contractIdFor =
    { service, adv, rawInterface, interfaceName, idx }:
    if builtins.isString (adv.id or null) && adv.id != "" then
      adv.id
    else if rawInterface != null then
      rawInterface
    else if interfaceName != null then
      interfaceName
    else
      "${service}-${builtins.toString (idx + 1)}";
in
{
  contractFor =
    { listName, service, adv, interfaceName, idx }:
    let
      rawInterface = rawInterfaceFor adv;
      advId = if builtins.isString (adv.id or null) && adv.id != "" then adv.id else null;
      contractId = contractIdFor {
        inherit service adv rawInterface interfaceName idx;
      };
      candidates = lib.filter
        (
          contract:
          (contract.service or null) == service
          && (
            (advId != null && (contract.id or null) == advId)
            || (rawInterface != null && (contract.interface or null) == rawInterface)
            || (interfaceName != null && (contract.interface or null) == interfaceName)
          )
        )
        (listFor listName);
    in
    if builtins.length candidates == 1 then
      builtins.head candidates
    else if candidates == [ ] then
      throw "CPM renderer contract update required: runtimeTarget.stateContracts.persistence.${listName} is missing ${service} lease-state contract '${contractId}'"
    else
      throw "CPM renderer contract update required: runtimeTarget.stateContracts.persistence.${listName} has ambiguous ${service} lease-state contract '${contractId}'";
}
