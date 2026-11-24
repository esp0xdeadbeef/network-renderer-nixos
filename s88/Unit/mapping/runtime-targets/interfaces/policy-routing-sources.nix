{ lib, common }:

interfaces: runtimeTarget:
let
  names = common.sortedAttrNames interfaces;

  renderedNameFor =
    name:
    let
      iface = interfaces.${name};
    in
    if builtins.isString (iface.renderedIfName or null) then iface.renderedIfName else name;

  backingRefFor =
    name:
    let
      backingRef = interfaces.${name}.backingRef or { };
    in
    if builtins.isAttrs backingRef then backingRef else { };

  laneFor =
    name:
    let
      lane = (backingRefFor name).lane or { };
    in
    if builtins.isAttrs lane then lane else { };

  laneAccessFor =
    name:
    let
      access = (laneFor name).access or null;
    in
    if builtins.isString access then access else null;

  uplinksFor =
    name:
    let
      backingRef = backingRefFor name;
      lane = laneFor name;
      explicit =
        if builtins.isList (backingRef.uplinks or null) then
          lib.filter builtins.isString backingRef.uplinks
        else
          [ ];
      laneUplinks =
        if builtins.isList (lane.uplinks or null) then lib.filter builtins.isString lane.uplinks else [ ];
    in
    lib.unique (explicit ++ laneUplinks);

  relations =
    let
      canonical =
        if builtins.isAttrs runtimeTarget then runtimeTarget.canonicalForwarding or { } else { };
      targetName = if builtins.isAttrs runtimeTarget then runtimeTarget.target or null else null;
    in
    builtins.filter (
      r: builtins.isAttrs r && (r.action or null) == "accept" && (r.target or null) == targetName
    ) (canonical.relations or [ ]);

  modelledForRendered =
    rendered:
    let
      hits = lib.filter (name: renderedNameFor name == rendered) names;
    in
    if hits == [ ] then null else builtins.head hits;

  sourcesFor =
    target:
    let
      renderedTarget = renderedNameFor target;
      forwardPeers = map (r: modelledForRendered (r.fromInterface or null)) (
        builtins.filter (r: (r.toInterface or null) == renderedTarget) relations
      );
      returnPeers = map (r: modelledForRendered (r.toInterface or null)) (
        builtins.filter (r: (r.fromInterface or null) == renderedTarget) relations
      );
      usable = lib.filter (n: n != null) (forwardPeers ++ returnPeers);
    in
    if usable == [ ] then [ target ] else lib.unique ([ target ] ++ usable);
in
builtins.listToAttrs (
  map (target: {
    name = renderedNameFor target;
    value = sourcesFor target;
  }) names
)
