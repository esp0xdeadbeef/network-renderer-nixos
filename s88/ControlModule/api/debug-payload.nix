{ lib
, system
, hostName
, hostContext
, intent
, globalInventory
, compilerOut
, forwardingOut
, controlPlaneOut
, renderedHostNetwork
}:

let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  concatMap = f: xs: builtins.concatLists (map f xs);

  sanitizeDebug =
    raw: if !builtins.isAttrs raw then { } else builtins.removeAttrs raw [ "profilePath" ];

  firstNonEmptyString =
    values: fallback:
    let
      strings = lib.filter (value: builtins.isString value && value != "") values;
    in
    if strings == [ ] then fallback else builtins.head strings;

  pathLabel = path: builtins.concatStringsSep "." path;

  collectTrafficPathValidations =
    path: value:
    let
      current =
        if builtins.isAttrs value
          && value ? trafficPathValidation
          && builtins.isAttrs value.trafficPathValidation then
          [
            {
              modelPath = path;
              inherit (value) trafficPathValidation;
            }
          ]
        else
          [ ];

      children =
        if builtins.isAttrs value then
          concatMap
            (name: collectTrafficPathValidations (path ++ [ name ]) value.${name})
            (sortedAttrNames value)
        else
          [ ];
    in
    current ++ children;

  controlPlaneData = controlPlaneOut.control_plane_model.data or { };

  trafficPathValidations =
    collectTrafficPathValidations [ "controlPlaneOut" "control_plane_model" "data" ] controlPlaneData;

  pathRows =
    key:
    concatMap
      (record:
        let
          paths = record.trafficPathValidation.${key} or [ ];
        in
        if builtins.isList paths then
          map
            (pathData: {
              inherit (record) modelPath;
              inherit pathData;
            })
            paths
        else
          [ ])
      trafficPathValidations;

  validPathRows = pathRows "validPaths";
  invalidPathRows = pathRows "invalidPaths";
  firstValidRow = if validPathRows == [ ] then null else builtins.head validPathRows;
  firstInvalidRow = if invalidPathRows == [ ] then null else builtins.head invalidPathRows;

  diagnosticRows =
    concatMap
      (record:
        let
          raw = record.trafficPathValidation.diagnostics or [ ];
        in
        if builtins.isList raw then
          map
            (diagnostic: {
              inherit (record) modelPath;
              inherit diagnostic;
            })
            raw
        else if builtins.isAttrs raw then
          map
            (name:
              let
                value = raw.${name};
              in
              {
                inherit (record) modelPath;
                diagnostic =
                  if builtins.isAttrs value then
                    value // { diagnosticName = name; }
                  else
                    {
                      diagnosticName = name;
                      diagnosticValue = value;
                    };
              })
            (sortedAttrNames raw)
        else
          [ ])
      trafficPathValidations;

  firstDiagnosticRow = if diagnosticRows == [ ] then null else builtins.head diagnosticRows;

  diagnosticString =
    diagnostic: field: fallback:
    if builtins.isAttrs diagnostic
      && builtins.hasAttr field diagnostic
      && builtins.isString diagnostic.${field}
      && diagnostic.${field} != "" then
      diagnostic.${field}
    else
      fallback;

  diagnosticReasonClass =
    diagnostic:
    if builtins.isAttrs diagnostic && (diagnostic.missingEvidence or false) == true then
      "missing-evidence"
    else if builtins.isAttrs diagnostic && (diagnostic.contractContradiction or false) == true then
      "contract-contradiction"
    else
      diagnosticString diagnostic "severity" "diagnostic";

  reachabilityEvidence =
    if firstValidRow == null then
      [ ]
    else
      let
        path = firstValidRow.pathData;
      in
      [
        {
          spec = "FS-500-HDS-010-SDS-010-SMS-010";
          kind = "reachability-decision";
          source = "controlPlaneOut.control_plane_model.data.*.trafficPathValidation.validPaths";
          modelPath = firstValidRow.modelPath;
          decision = {
            result = firstNonEmptyString [ (path.action or "") (path.pathAction or "") ] "modeled";
            trafficClass = firstNonEmptyString [ (path.trafficType or "") (path.protocol or "") ] "unknown";
            selectedPath = firstNonEmptyString [ (path.relationId or "") (path.p2pIsolationKey or "") ] (pathLabel firstValidRow.modelPath);
            egressSurface = path.nodePath or (path.stagePath or [ ]);
            returnBehavior = path.returnBehavior or "unspecified";
            serviceExposure = path.destination or "unknown";
          };
        }
      ];

  diagnosticEvidence =
    if firstDiagnosticRow != null then
      let
        diagnostic = firstDiagnosticRow.diagnostic;
      in
      [
        {
          spec = "FS-500-HDS-010-SDS-010-SMS-030";
          kind = "decision-reason";
          source = "controlPlaneOut.control_plane_model.data.*.trafficPathValidation.diagnostics";
          modelPath = firstDiagnosticRow.modelPath;
          diagnostic = {
            reason =
              firstNonEmptyString
                [
                  (diagnosticString diagnostic "message" "")
                  (diagnosticString diagnostic "reason" "")
                  (diagnosticString diagnostic "code" "")
                ]
                "traffic-path-validation-diagnostic";
            reasonClass = diagnosticReasonClass diagnostic;
            firstBlocker =
              firstNonEmptyString
                [
                  (diagnosticString diagnostic "relatedPath" "")
                  (diagnosticString diagnostic "firstBlocker" "")
                  (diagnosticString diagnostic "pathAction" "")
                ]
                (pathLabel firstDiagnosticRow.modelPath);
          };
        }
      ]
    else if firstInvalidRow != null then
      [
        {
          spec = "FS-500-HDS-010-SDS-010-SMS-030";
          kind = "decision-reason";
          source = "controlPlaneOut.control_plane_model.data.*.trafficPathValidation.invalidPaths";
          modelPath = firstInvalidRow.modelPath;
          diagnostic = {
            reason = firstNonEmptyString [ (firstInvalidRow.pathData.reason or "") (firstInvalidRow.pathData.code or "") ] "invalid-traffic-path";
            reasonClass = "invalid-path";
            firstBlocker = firstNonEmptyString [ (firstInvalidRow.pathData.relationId or "") (firstInvalidRow.pathData.p2pIsolationKey or "") ] (pathLabel firstInvalidRow.modelPath);
          };
        }
      ]
    else if firstValidRow != null then
      [
        {
          spec = "FS-500-HDS-010-SDS-010-SMS-030";
          kind = "decision-reason";
          source = "controlPlaneOut.control_plane_model.data.*.trafficPathValidation.validPaths";
          modelPath = firstValidRow.modelPath;
          diagnostic = {
            reason = "no-invalid-traffic-paths";
            reasonClass = "no-false-positive";
            firstBlocker = "none";
          };
        }
      ]
    else
      [ ];

  dnsHatEvidence = reachabilityEvidence ++ diagnosticEvidence;

  sanitizeContainer =
    containerName: container:
    let
      specialArgs =
        if container ? specialArgs && builtins.isAttrs container.specialArgs then
          container.specialArgs
        else
          { };

      firewall =
        if specialArgs ? s88Firewall then
          let
            rawFirewall = specialArgs.s88Firewall;
          in
          if builtins.isAttrs rawFirewall then
            {
              enable = rawFirewall.enable or false;
              ruleset = if rawFirewall ? ruleset then rawFirewall.ruleset else null;
            }
          else if builtins.isString rawFirewall then
            {
              enable = rawFirewall != "";
              ruleset = rawFirewall;
            }
          else
            {
              enable = false;
              ruleset = null;
            }
        else
          {
            enable = false;
            ruleset = null;
          };

      s88Debug =
        if specialArgs ? s88Debug && builtins.isAttrs specialArgs.s88Debug then
          sanitizeDebug specialArgs.s88Debug
        else
          { };

      s88Warnings =
        if specialArgs ? s88Warnings && builtins.isList specialArgs.s88Warnings then
          lib.filter builtins.isString specialArgs.s88Warnings
        else
          [ ];

      s88Alarms =
        if specialArgs ? s88Alarms && builtins.isList specialArgs.s88Alarms then
          specialArgs.s88Alarms
        else
          [ ];
    in
    {
      autoStart = container.autoStart or false;
      privateNetwork = container.privateNetwork or false;
      extraVeths = container.extraVeths or { };
      bindMounts = container.bindMounts or { };
      allowedDevices = container.allowedDevices or [ ];
      additionalCapabilities = container.additionalCapabilities or [ ];
      inherit firewall;
      warnings = s88Warnings;
      alarms = s88Alarms;
      specialArgs = {
        unitName = if specialArgs ? unitName then specialArgs.unitName else containerName;
        deploymentHostName =
          if specialArgs ? deploymentHostName then specialArgs.deploymentHostName else null;
        s88RoleName = if specialArgs ? s88RoleName then specialArgs.s88RoleName else null;
        s88Debug = s88Debug;
      };
    };

  sanitizedContainers = builtins.listToAttrs (
    map
      (containerName: {
        name = containerName;
        value = sanitizeContainer containerName renderedHostNetwork.containers.${containerName};
      })
      (sortedAttrNames (renderedHostNetwork.containers or { }))
  );
in
{
  inherit
    system
    hostName
    hostContext
    intent
    globalInventory
    compilerOut
    forwardingOut
    controlPlaneOut
    dnsHatEvidence
    ;

  renderedHost = {
    hostName = renderedHostNetwork.hostName or null;
    deploymentHostName = renderedHostNetwork.deploymentHostName or null;
    runtimeRole = renderedHostNetwork.runtimeRole or null;
    selectedUnits = renderedHostNetwork.selectedUnits or [ ];
    selectedRoleNames = renderedHostNetwork.selectedRoleNames or [ ];
    bridgeNameMap = renderedHostNetwork.bridgeNameMap or { };
    bridges = renderedHostNetwork.bridges or { };
    netdevs = renderedHostNetwork.netdevs or { };
    networks = renderedHostNetwork.networks or { };
    attachTargets = renderedHostNetwork.attachTargets or [ ];
    localAttachTargets = renderedHostNetwork.localAttachTargets or [ ];
    uplinks = renderedHostNetwork.uplinks or { };
    transitBridges = renderedHostNetwork.transitBridges or { };
    containers = sanitizedContainers;
    debug = renderedHostNetwork.debug or { };
  };
}
