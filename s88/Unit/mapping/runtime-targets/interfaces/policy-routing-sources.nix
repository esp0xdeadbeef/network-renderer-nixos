{ lib, common }:

interfaces:
let
  names = common.sortedAttrNames interfaces;

  renderedNameFor =
    name:
    let iface = interfaces.${name};
    in
    if builtins.isString (iface.renderedIfName or null) then iface.renderedIfName else name;

  classFor = name:
    let ifaceClass = interfaces.${name}.interfaceClass or { };
    in if builtins.isAttrs ifaceClass then ifaceClass else { };

  backingRefFor = name:
    let backingRef = interfaces.${name}.backingRef or { };
    in if builtins.isAttrs backingRef then backingRef else { };

  laneFor = name:
    let lane = (backingRefFor name).lane or { };
    in if builtins.isAttrs lane then lane else { };

  laneAccessFor = name:
    let access = (laneFor name).access or null;
    in if builtins.isString access then access else null;

  uplinksFor = name:
    let
      backingRef = backingRefFor name;
      lane = laneFor name;
      explicit = if builtins.isList (backingRef.uplinks or null) then lib.filter builtins.isString backingRef.uplinks else [ ];
      laneUplinks = if builtins.isList (lane.uplinks or null) then lib.filter builtins.isString lane.uplinks else [ ];
    in
    lib.unique (explicit ++ laneUplinks);

  sameAccess = left: right:
    let access = laneAccessFor left;
    in access != null && laneAccessFor right == access;

  sameUplink = left: right:
    lib.any (uplink: builtins.elem uplink (uplinksFor right)) (uplinksFor left);

  hasClass = flag: name: (classFor name).${flag} or false;

  isSelector = lib.any (hasClass "edgeFacing") names && lib.any (hasClass "fabricFacing") names;
  isUpstreamSelector = lib.any (hasClass "coreFacing") names && lib.any (hasClass "exitFacing") names;
  isPolicy = lib.any (hasClass "fabricFacing") names && lib.any (hasClass "exitFacing") names;

  sourcesFor =
    target:
    if isSelector && hasClass "edgeFacing" target then
      lib.filter (name: hasClass "fabricFacing" name && sameAccess target name) names
    else if isSelector && hasClass "fabricFacing" target then
      lib.filter (name: hasClass "edgeFacing" name && sameAccess target name) names
    else if isUpstreamSelector && hasClass "coreFacing" target then
      lib.unique ([ target ] ++ lib.filter (hasClass "exitFacing") names)
    else if isUpstreamSelector && hasClass "exitFacing" target then
      lib.unique ([ target ] ++ lib.filter (name: hasClass "coreFacing" name && sameUplink target name) names)
    else if isPolicy && hasClass "fabricFacing" target then
      lib.filter (name: hasClass "fabricFacing" name || (hasClass "exitFacing" name && sameAccess target name)) names
    else if isPolicy && hasClass "exitFacing" target then
      lib.filter (name: (hasClass "fabricFacing" name || hasClass "exitFacing" name) && sameAccess target name) names
    else if hasClass "overlay" target then
      lib.unique ([ target ] ++ lib.filter (hasClass "coreTransit") names)
    else if hasClass "coreTransit" target then
      lib.unique ([ target ] ++ lib.filter (hasClass "overlay") names)
    else
      [ target ];
in
builtins.listToAttrs (
  map
    (target: {
      name = renderedNameFor target;
      value = sourcesFor target;
    })
    names
)
