{ lib
, cpm ? null
, flakeInputs ? null
, runtimeTarget ? { }
, unitName ? null
, containerName ? null
, roleName ? null
, assumptionFamily ? null
, interfaces ? { }
, wanIfs ? [ ]
, lanIfs ? [ ]
, uplinks ? { }
, interfaceView ? null
, forwardingIntent ? null
, communication ? null
, endpointMap ? null
,
}:

let
  isa = import ../../alarm/isa18.nix { inherit lib; };

  interfaceViewResolved =
    if interfaceView != null then
      interfaceView
    else
      import ./interface-view.nix {
        inherit
          lib
          interfaces
          wanIfs
          lanIfs
          ;
      };

  forwardingIntentResolved =
    if forwardingIntent != null then
      forwardingIntent
    else
      import ./forwarding-intent.nix {
        inherit
          lib
          runtimeTarget
          interfaces
          wanIfs
          lanIfs
          uplinks
          ;
      };

  communicationResolved =
    if communication != null then
      communication
    else if cpm != null then
      import ./communication-contract.nix
        {
          inherit
            lib
            cpm
            flakeInputs
            runtimeTarget
            ;
        }
    else
      {
        currentRootName = null;
        currentSiteName = null;
        currentSite = { };
        forwardingModel = { };
        forwardingSite = { };
        communicationContract = { };
        ownership = { };
      };

  endpointMapResolved =
    if endpointMap != null then
      endpointMap
    else if cpm != null then
      import ../mapping/policy-endpoints.nix
        {
          inherit
            lib
            runtimeTarget
            roleName
            unitName
            containerName
            ;
          interfaceView = interfaceViewResolved;
          currentSite = communicationResolved.currentSite;
          communicationContract = communicationResolved.communicationContract;
          ownership = communicationResolved.ownership;
        }
    else
      {
        resolveEndpoint = _: [ ];
        allKnownInterfaces = [ ];
        wanNames = interfaceViewResolved.wanNames or [ ];
        p2pNames = [ ];
        localAdapterNames = interfaceViewResolved.lanNames or [ ];
        authoritativeBindings = false;
        authorityGaps = [ ];
      };

  sortedStrings =
    values:
    lib.sort builtins.lessThan (
      lib.unique (lib.filter (value: builtins.isString value && value != "") values)
    );

  sourceKindOf =
    entry:
    if entry ? sourceKind && builtins.isString entry.sourceKind then
      entry.sourceKind
    else if
      entry ? iface
      && builtins.isAttrs entry.iface
      && entry.iface ? sourceKind
      && builtins.isString entry.iface.sourceKind
    then
      entry.iface.sourceKind
    else
      null;

  interfaceEntries =
    if interfaceViewResolved ? interfaceEntries && builtins.isList interfaceViewResolved.interfaceEntries then
      interfaceViewResolved.interfaceEntries
    else
      [ ];

  interfaceNames = sortedStrings (map (entry: entry.name or null) interfaceEntries);

  fallbackWanNames =
    if interfaceViewResolved ? wanNames && builtins.isList interfaceViewResolved.wanNames then
      sortedStrings interfaceViewResolved.wanNames
    else
      [ ];

  fallbackLanNames =
    if interfaceViewResolved ? lanNames && builtins.isList interfaceViewResolved.lanNames then
      sortedStrings interfaceViewResolved.lanNames
    else
      [ ];

  fallbackP2pNames = sortedStrings (
    map (entry: entry.name or null) (lib.filter (entry: sourceKindOf entry == "p2p") interfaceEntries)
  );

  wanNames =
    if forwardingIntentResolved ? resolvedWanNames && builtins.isList forwardingIntentResolved.resolvedWanNames then
      sortedStrings forwardingIntentResolved.resolvedWanNames
    else
      fallbackWanNames;

  lanNames =
    if forwardingIntentResolved ? resolvedLanNames && builtins.isList forwardingIntentResolved.resolvedLanNames then
      sortedStrings forwardingIntentResolved.resolvedLanNames
    else
      fallbackLanNames;

  p2pNames =
    if
      forwardingIntentResolved ? resolvedTransitNames && builtins.isList forwardingIntentResolved.resolvedTransitNames
    then
      sortedStrings forwardingIntentResolved.resolvedTransitNames
    else
      fallbackP2pNames;

  localAdapterNames =
    if
      forwardingIntentResolved ? resolvedLocalAdapterNames
      && builtins.isList forwardingIntentResolved.resolvedLocalAdapterNames
    then
      sortedStrings forwardingIntentResolved.resolvedLocalAdapterNames
    else
      sortedStrings (
        map (entry: entry.name or null) (
          lib.filter
            (
              entry:
              let
                sourceKind = sourceKindOf entry;
              in
              sourceKind != "wan" && sourceKind != "p2p"
            )
            interfaceEntries
        )
      );

  accessUplinkNames =
    if
      forwardingIntentResolved ? resolvedAccessUplinkNames
      && builtins.isList forwardingIntentResolved.resolvedAccessUplinkNames
    then
      sortedStrings forwardingIntentResolved.resolvedAccessUplinkNames
    else if p2pNames != [ ] then
      p2pNames
    else
      wanNames;

  uplinkNames =
    if builtins.isAttrs uplinks then lib.sort builtins.lessThan (builtins.attrNames uplinks) else [ ];

  entityName =
    if builtins.isString containerName && containerName != "" then
      containerName
    else if builtins.isString unitName && unitName != "" then
      unitName
    else
      null;

  alarms = import ./assumptions/alarms.nix {
    inherit
      lib
      isa
      assumptionFamily
      roleName
      entityName
      interfaceNames
      localAdapterNames
      accessUplinkNames
      forwardingIntentResolved
      wanNames
      lanNames
      uplinkNames
      p2pNames
      communicationResolved
      endpointMapResolved
      ;
  };

  warningMessages = isa.warningsFromAlarms alarms;
in
{
  inherit alarms warningMessages;
  warnings = warningMessages;
}
