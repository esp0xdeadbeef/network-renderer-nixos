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

  interfaceEntries =
    if interfaceViewResolved ? interfaceEntries && builtins.isList interfaceViewResolved.interfaceEntries then
      interfaceViewResolved.interfaceEntries
    else
      [ ];

  interfaceNames = sortedStrings (map (entry: entry.name or null) interfaceEntries);

  roleListFields = [
    "resolvedWanNames"
    "resolvedLanNames"
    "resolvedTransitNames"
    "resolvedLocalAdapterNames"
    "resolvedAccessUplinkNames"
  ];

  hasRoleListField =
    field:
    builtins.hasAttr field forwardingIntentResolved
    && builtins.isList forwardingIntentResolved.${field};

  explicitRoleContractPresent =
    if builtins.hasAttr "explicitRoleContractPresent" forwardingIntentResolved then
      forwardingIntentResolved.explicitRoleContractPresent
    else
      builtins.all hasRoleListField roleListFields;

  missingRoleListFields = lib.filter (field: !(hasRoleListField field)) roleListFields;

  missingRoleContractInterfaces =
    if
      forwardingIntentResolved ? missingExplicitRoleContractInterfaces
      && builtins.isList forwardingIntentResolved.missingExplicitRoleContractInterfaces
    then
      forwardingIntentResolved.missingExplicitRoleContractInterfaces
    else
      [ ];

  roleContractDiagnostic =
    builtins.concatStringsSep " " (
      [
        "FS-320-HDS-040-SDS-010-SMS-060: missing CPM explicit role contract for NixOS interface role classification;"
        "renderer must not derive WAN, transit, LAN, local-adapter, or access-uplink roles from sourceKind tokens or interface names."
      ]
      ++ lib.optionals (missingRoleListFields != [ ]) [
        "Missing forwardingIntent fields: ${builtins.concatStringsSep ", " missingRoleListFields}."
      ]
      ++ lib.optionals (missingRoleContractInterfaces != [ ]) [
        "Interfaces without explicit role booleans: ${builtins.concatStringsSep ", " missingRoleContractInterfaces}."
      ]
    );

  requireExplicitRoleContract =
    value:
    if interfaceNames != [ ] && !explicitRoleContractPresent then
      throw roleContractDiagnostic
    else
      value;

  roleListOrThrow =
    field:
    requireExplicitRoleContract (
      if hasRoleListField field then
        sortedStrings forwardingIntentResolved.${field}
      else
        throw roleContractDiagnostic
    );

  wanNames = roleListOrThrow "resolvedWanNames";

  lanNames = roleListOrThrow "resolvedLanNames";

  p2pNames = roleListOrThrow "resolvedTransitNames";

  localAdapterNames = roleListOrThrow "resolvedLocalAdapterNames";

  accessUplinkNames = roleListOrThrow "resolvedAccessUplinkNames";

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
