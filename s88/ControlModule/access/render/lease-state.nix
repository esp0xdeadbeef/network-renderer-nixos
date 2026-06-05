{ service, fileStem, suffix ? "" }:

let
  requiredField =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "NixOS ${service} renderer requires scope.leaseState.${name}";
in
leaseState:
let
  checkedState =
    if builtins.isAttrs leaseState then
      leaseState
    else
      throw "NixOS ${service} renderer state-loss classification: required persistent state is unavailable because explicit scope.leaseState from CPM stateContracts.persistence is missing";
  rawMode = requiredField "mode" (checkedState.mode or null);
  mode =
    if rawMode == "persistent" || rawMode == "ephemeral" then
      rawMode
    else
      throw "NixOS ${service} renderer requires scope.leaseState.mode to be persistent or ephemeral";
  path =
    if builtins.isString (checkedState.path or null) && checkedState.path != "" then
      checkedState.path
    else if mode == "ephemeral" && (checkedState.runtimeLocation or null) == "ephemeral" then
      "/run/kea/${fileStem}${suffix}.leases"
    else
      throw "NixOS ${service} renderer state-loss classification: required persistent state for ${fileStem} is unavailable because scope.leaseState.path is missing and runtimeLocation=ephemeral was not selected";
  persist = mode == "persistent";
in
{
  inherit mode path persist;
  directory = builtins.dirOf path;
}
