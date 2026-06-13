{ outPath
, lib
, config
, selector ? null
, hostContext ? { }
, globalInventory ? { }
, fabricInputs ? { }
,
}:

# NOTE: pathsFromOutPath usage removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
# Callers must provide already-loaded fabricInputs and globalInventory,
# not filesystem paths to intent.nix/inventory.nix.

let
  hostQuery = import ../../../ControlModule/lookup/host-query.nix { inherit lib; };

  hostSelector = if selector != null then selector else config.networking.hostName;

  queried = hostQuery.query {
    selector = hostSelector;
    intent = fabricInputs;
    inventory = globalInventory;
    file = "s88/Unit/router/lookup/default.nix";
  };

  resolvedHostContext = if hostContext != { } then hostContext else queried.hostContext;
  resolvedInventory = if globalInventory != { } then globalInventory else queried.globalInventory;
in
{
  inherit
    queried
    hostSelector
    resolvedHostContext
    resolvedInventory
    ;

  fabricInputs = queried.fabricInputs;
}
