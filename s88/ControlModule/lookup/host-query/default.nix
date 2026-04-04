{ lib }:

let
  pathLookup = import ./paths.nix { inherit lib; };
  inventoryLookup = import ./inventory.nix { inherit lib; };

  query =
    {
      selector ? null,
      hostname ? null,
      intent ? null,
      inventory ? null,
      intentPath ? null,
      inventoryPath ? null,
      file ? "s88/ControlModule/lookup/host-query.nix",
    }:
    let
      effectiveSelector =
        if selector != null then
          selector
        else if hostname != null then
          hostname
        else
          throw "${file}: query requires either selector or hostname";

      fabricInputs =
        if intent != null then
          intent
        else if intentPath != null then
          pathLookup.importMaybeFunction intentPath
        else
          { };

      globalInventory =
        if inventory != null then
          inventory
        else if inventoryPath != null then
          pathLookup.importMaybeFunction inventoryPath
        else
          { };
    in
    {
      inherit fabricInputs globalInventory;
      hostContext = inventoryLookup.hostContextForSelector {
        selector = effectiveSelector;
        intent = fabricInputs;
        inventory = globalInventory;
        inherit file;
      };
    };

  queryFromOutPath =
    {
      outPath,
      hostname,
      fabricRoot ? null,
      file ? "s88/ControlModule/lookup/host-query.nix",
    }:
    let
      paths = pathLookup.pathsFromOutPath {
        inherit outPath fabricRoot;
      };
    in
    query {
      inherit hostname file;
      inherit (paths) intentPath inventoryPath;
    };
in
pathLookup
// inventoryLookup
// {
  inherit
    query
    queryFromOutPath
    ;
}
