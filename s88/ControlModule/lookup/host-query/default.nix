{ lib }:

let
  pathLookup = import ./paths.nix { inherit lib; };
  sourceLookup = import ./inventory.nix { inherit lib; };

  # NOTE: CMC-NIXOS-INTENT-CLEANUP: 'inventory' renamed to 'source'.
  # Per FS-310-HDS-010-SDS-010-SMS-100/101, renderers consume ONLY CPM-mediated data.
  # Callers must provide already-loaded source objects (CPM-extracted), not filesystem paths.
  query =
    { selector ? null
    , hostname ? null
    , intent ? null
    , inventory ? null   # kept for backward compat, prefer 'source'
    , source ? null
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

      # Resolved source: prefer explicit 'source', fall back to 'inventory' for backward compat
      resolvedSource =
        if source != null then
          source
        else if inventory != null then
          inventory
        else
          { };
    in
    {
      inherit fabricInputs;
      globalInventory = resolvedSource;
      hostContext = sourceLookup.hostContextForSelector {
        selector = effectiveSelector;
        intent = fabricInputs;
        source = resolvedSource;
        inherit file;
      };
    };

  # NOTE: queryFromOutPath removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
  # Constructing filesystem paths to upstream intent.nix/inventory.nix is a violation.
in
pathLookup
// sourceLookup
  // {
  inherit
    query
    ;
}
