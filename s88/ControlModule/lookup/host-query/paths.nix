{ lib }:

let
  callIfFunction = value: if builtins.isFunction value then value { inherit lib; } else value;

  importMaybeFunction =
    path:
    if builtins.pathExists path then
      callIfFunction (import path)
    else
      throw "s88/ControlModule/lookup/host-query.nix: missing required input path '${builtins.toString path}'";

  loadStructuredPath =
    path:
    let
      pathString = builtins.toString path;
    in
    if !builtins.pathExists path then
      throw "s88/ControlModule/lookup/host-query.nix: missing required input path '${pathString}'"
    else if lib.hasSuffix ".json" pathString then
      builtins.fromJSON (builtins.readFile path)
    else
      callIfFunction (import path);

  # NOTE: pathsFromOutPath, loadInputs, loadInputsFromOutPath removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
  # Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
  # Constructing filesystem paths to upstream intent.nix/inventory.nix is a violation.
  # Callers must provide already-loaded CPM-mediated data, not file paths.
in
{
  inherit
    importMaybeFunction
    loadStructuredPath
    ;
}
