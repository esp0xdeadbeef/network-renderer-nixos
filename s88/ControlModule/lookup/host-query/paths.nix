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

  firstExistingPath =
    candidates:
    let
      existing = builtins.filter builtins.pathExists candidates;
    in
    if existing == [ ] then null else builtins.head existing;

  repoRootFromOutPath = outPath: builtins.dirOf (builtins.dirOf (builtins.dirOf outPath));

  fabricRootFromOutPath =
    outPath: builtins.toPath "${repoRootFromOutPath outPath}/library/100-fabric-routing";

  pathsFromOutPath =
    {
      outPath,
      fabricRoot ? null,
    }:
    let
      resolvedFabricRoot = if fabricRoot != null then fabricRoot else fabricRootFromOutPath outPath;

      intentCandidates = [
        "${outPath}/library/100-fabric-routing/inputs/intent.nix"
        "${outPath}/inputs/intent.nix"
        "${outPath}/intent.nix"
        "${resolvedFabricRoot}/inputs/intent.nix"
      ];

      inventoryCandidates = [
        "${outPath}/library/100-fabric-routing/inputs/inventory-nixos.nix"
        "${outPath}/library/100-fabric-routing/inputs/inventory.nix"
        "${outPath}/library/100-fabric-routing/inventory-nixos.nix"
        "${outPath}/library/100-fabric-routing/inventory.nix"
        "${outPath}/inputs/inventory-nixos.nix"
        "${outPath}/inputs/inventory.nix"
        "${outPath}/inventory-nixos.nix"
        "${outPath}/inventory.nix"
        "${resolvedFabricRoot}/inputs/inventory-nixos.nix"
        "${resolvedFabricRoot}/inputs/inventory.nix"
        "${resolvedFabricRoot}/inventory-nixos.nix"
        "${resolvedFabricRoot}/inventory.nix"
      ];
    in
    {
      intentPath =
        let
          selected = firstExistingPath intentCandidates;
        in
        if selected == null then builtins.head intentCandidates else selected;

      inventoryPath =
        let
          selected = firstExistingPath inventoryCandidates;
        in
        if selected == null then builtins.head inventoryCandidates else selected;
    };

  loadInputs =
    {
      intentPath,
      inventoryPath,
    }:
    {
      fabricInputs = importMaybeFunction intentPath;
      globalInventory = importMaybeFunction inventoryPath;
    };

  loadInputsFromOutPath =
    {
      outPath,
      fabricRoot ? null,
    }:
    let
      paths = pathsFromOutPath {
        inherit outPath fabricRoot;
      };
    in
    loadInputs {
      inherit (paths) intentPath inventoryPath;
    };
in
{
  inherit
    importMaybeFunction
    loadStructuredPath
    repoRootFromOutPath
    fabricRootFromOutPath
    pathsFromOutPath
    loadInputs
    loadInputsFromOutPath
    ;
}
