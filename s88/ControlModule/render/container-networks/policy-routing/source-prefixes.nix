{
  lib,
  containerModel,
  laneAccessForRenderedName,
  sourceKindForRenderedName,
}:

let
  tenantPrefixOwners =
    if builtins.isAttrs (containerModel.site.tenantPrefixOwners or null) then
      containerModel.site.tenantPrefixOwners
    else
      { };

  entryFor =
    key: value:
    let
      parts = lib.splitString "|" key;
      familyPart = if builtins.length parts >= 1 then builtins.elemAt parts 0 else "";
      prefixPart = if builtins.length parts >= 2 then builtins.elemAt parts 1 else "";
      family = if familyPart == "6" then 6 else 4;
      owner = value.owner or null;
      sourceFile =
        if builtins.isString (value.sourceFile or null) && value.sourceFile != "" then
          value.sourceFile
        else if lib.hasPrefix "source:" prefixPart then
          lib.removePrefix "source:" prefixPart
        else
          null;
    in
    if !(builtins.isString owner) || owner == "" then
      null
    else if sourceFile != null then
      {
        inherit family owner sourceFile;
        kind = "sourceFile";
      }
    else if prefixPart != "" then
      {
        inherit family owner;
        prefix = prefixPart;
        kind = "static";
      }
    else
      null;

  entries = lib.filter (entry: entry != null) (lib.mapAttrsToList entryFor tenantPrefixOwners);

  scopeForAccess =
    access:
    let
      owned = lib.filter (entry: entry.owner == access) entries;
    in
    {
      staticPrefixes = map (entry: { inherit (entry) family prefix; }) (
        lib.filter (entry: entry.kind == "static") owned
      );
      sourceFiles = map (entry: { inherit (entry) family sourceFile; }) (
        lib.filter (entry: entry.kind == "sourceFile") owned
      );
    };

  # The core fabric p2p carries every tenant's forwarded traffic without its
  # own access lane, so it must be source-scoped by all tenant prefixes rather
  # than by a single access unit.
  allTenantsScope = {
    staticPrefixes = map (entry: { inherit (entry) family prefix; }) (
      lib.filter (entry: entry.kind == "static") entries
    );
    sourceFiles = map (entry: { inherit (entry) family sourceFile; }) (
      lib.filter (entry: entry.kind == "sourceFile") entries
    );
  };
in
{
  forInterface =
    interfaceName:
    let
      access = laneAccessForRenderedName interfaceName;
      sourceKind = sourceKindForRenderedName interfaceName;
    in
    if access != null then
      scopeForAccess access
    else if sourceKind == "p2p" then
      allTenantsScope
    else
      {
        staticPrefixes = [ ];
        sourceFiles = [ ];
      };
}
