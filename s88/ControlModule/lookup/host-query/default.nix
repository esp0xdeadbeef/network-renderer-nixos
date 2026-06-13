{ lib }:

let
  pathLookup = import ./paths.nix { inherit lib; };
  inventoryLookup = import ./inventory.nix { inherit lib; };

  # NOTE: intentPath/inventoryPath params removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
  # Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM-mediated data.
  # Callers must provide already-loaded intent/inventory objects, not filesystem paths.
  query =
    { selector ? null
    , hostname ? null
    , intent ? null
    , inventory ? null
    , file ? "s88/ControlModule/lookup/host-query.nix"
    ,
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
        else
          { };

      globalInventory =
        if inventory != null then
          inventory
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

  # NOTE: queryFromOutPath removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
  # Constructing filesystem paths to upstream intent.nix/inventory.nix is a violation.
in
pathLookup
// inventoryLookup
  // {
  inherit
    query
    ;
}
