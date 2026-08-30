{
  lib,
  containerModel,
  laneAccessForRenderedName,
  sourceKindForRenderedName,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  addressForFamily,
  ipv4PeerFor31,
  ipv6PeerFor127,
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

  backingRefForInterface =
    iface:
    if iface ? backingRef && builtins.isAttrs iface.backingRef then
      iface.backingRef
    else if
      iface ? connectivity
      && builtins.isAttrs iface.connectivity
      && iface.connectivity ? backingRef
      && builtins.isAttrs iface.connectivity.backingRef
    then
      iface.connectivity.backingRef
    else
      { };

  laneForInterface =
    iface:
    let
      ref = backingRefForInterface iface;
      lane = if builtins.isAttrs ref then (ref.lane or { }) else { };
    in
    if builtins.isAttrs lane then lane else { };

  fabricPeerPrefixesForAccess =
    access:
    let
      accessEdgeIfNames = lib.filter (
        ifName:
        let
          lane = laneForInterface interfaces.${ifName};
        in
        (lane.access or null) == access && (lane.kind or null) == "access-edge"
      ) interfaceNames;
      peerPrefix =
        ifName: family:
        let
          iface = interfaces.${ifName};
          address = addressForFamily family iface;
          peer = if family == 6 then ipv6PeerFor127 address else ipv4PeerFor31 address;
          hostLength = if family == 6 then 128 else 32;
        in
        if !(builtins.isString peer) || peer == "" then
          null
        else
          {
            inherit family;
            prefix = "${peer}/${builtins.toString hostLength}";
          };
    in
    lib.filter (prefix: prefix != null) (
      lib.concatMap (ifName: [
        (peerPrefix ifName 4)
        (peerPrefix ifName 6)
      ]) accessEdgeIfNames
    );

  scopeForAccess =
    access:
    let
      owned = lib.filter (entry: entry.owner == access) entries;
      fabricPeers = fabricPeerPrefixesForAccess access;
    in
    {
      staticPrefixes =
        map (entry: { inherit (entry) family prefix; }) (lib.filter (entry: entry.kind == "static") owned)
        ++ fabricPeers;
      sourceFiles = map (entry: { inherit (entry) family sourceFile; }) (
        lib.filter (entry: entry.kind == "sourceFile") owned
      );
    };

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
