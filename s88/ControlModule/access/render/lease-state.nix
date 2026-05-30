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
      throw "NixOS ${service} renderer requires explicit scope.leaseState from CPM stateContracts.persistence";
  mode = requiredField "mode" (checkedState.mode or null);
  path =
    if builtins.isString (checkedState.path or null) && checkedState.path != "" then
      checkedState.path
    else if mode == "ephemeral" && (checkedState.runtimeLocation or null) == "ephemeral" then
      "/run/kea/${fileStem}${suffix}.leases"
    else
      throw "NixOS ${service} renderer requires scope.leaseState.path for persistent lease state or runtimeLocation=ephemeral";
  persist =
    if mode == "persistent" then
      true
    else if mode == "ephemeral" then
      false
    else
      throw "NixOS ${service} renderer requires scope.leaseState.mode to be persistent or ephemeral";
in
{
  inherit mode path persist;
  directory = builtins.dirOf path;
}
