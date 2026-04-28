{
  lib,
  hostPlan ? null,
  cpm ? null,
  inventory ? { },
  debugEnabled ? false,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let
  inputs = import ./inputs.nix {
    inherit
      lib
      hostPlan
      containerModelsByHost
      containerModels
      deploymentContainers
      models
      ;
  };

  sortedNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  pad4 =
    value:
    let
      len = builtins.stringLength value;
    in
    if len >= 4 then
      value
    else if len == 3 then
      "0${value}"
    else if len == 2 then
      "00${value}"
    else if len == 1 then
      "000${value}"
    else
      "0000";

  expandedIpv6Cidr =
    prefix:
    let
      cidrMatch = builtins.match "([^/]+)/([0-9]+)" prefix;
      address = if cidrMatch == null then null else builtins.elemAt cidrMatch 0;
      prefixLen = if cidrMatch == null then null else builtins.elemAt cidrMatch 1;
      halves = if address == null then [ ] else lib.splitString "::" address;
      hasCompression = builtins.length halves == 2;
      left = if halves == [ ] then [ ] else lib.filter (part: part != "") (lib.splitString ":" (builtins.elemAt halves 0));
      right =
        if hasCompression then
          lib.filter (part: part != "") (lib.splitString ":" (builtins.elemAt halves 1))
        else
          [ ];
      missing = 8 - (builtins.length left) - (builtins.length right);
      groups =
        if address == null then
          [ ]
        else if hasCompression then
          left ++ (lib.replicate missing "0") ++ right
        else
          lib.splitString ":" address;
    in
    if cidrMatch == null || builtins.length groups != 8 then
      null
    else
      "${lib.concatStringsSep ":" (map pad4 groups)}/${prefixLen}";

  externalValidationDelegatedPrefixSources =
    let
      enterprises =
        if
          cpm ? control_plane_model
          && builtins.isAttrs cpm.control_plane_model
          && cpm.control_plane_model ? data
          && builtins.isAttrs cpm.control_plane_model.data
        then
          cpm.control_plane_model.data
        else if cpm ? data && builtins.isAttrs cpm.data then
          cpm.data
        else
          { };
    in
    builtins.foldl'
      (
        acc: enterpriseName:
        let
          enterprise = enterprises.${enterpriseName};
          sites = if builtins.isAttrs enterprise then enterprise else { };
        in
        builtins.foldl'
          (
            enterpriseAcc: siteName:
            let
              site = sites.${siteName};
              runtimeTargets =
                if site ? runtimeTargets && builtins.isAttrs site.runtimeTargets then
                  site.runtimeTargets
                else
                  { };
            in
            builtins.foldl'
              (
                siteAcc: targetName:
                let
                  target = runtimeTargets.${targetName};
                  externalValidation =
                    if target ? externalValidation && builtins.isAttrs target.externalValidation then
                      target.externalValidation
                    else
                      { };
                  sourceFile = externalValidation.delegatedPrefixSecretPath or null;
                  advertisements =
                    if target ? advertisements && builtins.isAttrs target.advertisements then
                      target.advertisements
                    else
                      { };
                  ipv6Ra =
                    if advertisements ? ipv6Ra && builtins.isList advertisements.ipv6Ra then
                      advertisements.ipv6Ra
                    else
                      [ ];
                  prefixesForAdvertisement =
                    adv:
                    let
                      explicitPrefixes =
                        if adv ? prefixes && builtins.isList adv.prefixes then
                          lib.filter builtins.isString adv.prefixes
                        else
                          [ ];
                      delegatedSubnet =
                        if
                          builtins.isString sourceFile
                          && sourceFile != ""
                          && adv ? externalValidation
                          && builtins.isAttrs adv.externalValidation
                          && builtins.isString (adv.routerInterface.subnet6 or null)
                        then
                          [ adv.routerInterface.subnet6 ]
                        else
                          [ ];
                    in
                    explicitPrefixes ++ delegatedSubnet;
                  prefixes =
                    lib.concatLists (
                      map (
                        adv: prefixesForAdvertisement adv
                      ) (lib.filter builtins.isAttrs ipv6Ra)
                    );
                in
                if builtins.isString sourceFile && sourceFile != "" then
                  siteAcc
                  // builtins.listToAttrs (
                    lib.concatLists (
                      map
                        (prefix:
                          let
                            expanded = expandedIpv6Cidr prefix;
                          in
                          [
                            {
                              name = prefix;
                              value = sourceFile;
                            }
                          ]
                          ++ lib.optionals (expanded != null && expanded != prefix) [
                            {
                              name = expanded;
                              value = sourceFile;
                            }
                          ])
                        prefixes
                    )
                  )
                else
                  siteAcc
              )
              enterpriseAcc
              (sortedNames runtimeTargets)
          )
          acc
          (sortedNames sites)
      )
      { }
      (sortedNames enterprises);

  renderModel =
    model:
    (import ./mapping.nix { inherit lib model; })
    // lib.optionalAttrs (externalValidationDelegatedPrefixSources != { }) {
      inherit externalValidationDelegatedPrefixSources;
    };

  firewallArgForModel =
    renderedModel:
    import ./firewall.nix {
      inherit
        lib
        cpm
        inventory
        renderedModel
        ;
      uplinks = inputs.uplinks;
    };

  alarmModelForRenderedModel =
    renderedModel:
    import ./alarms.nix {
      inherit
        lib
        cpm
        renderedModel
        ;
      uplinks = inputs.uplinks;
    };

  emitContainer =
    deploymentHostName: containerName: model:
    let
      renderedModel = renderModel model;
      firewallArg = firewallArgForModel renderedModel;
      alarmModel = alarmModelForRenderedModel renderedModel;
    in
    import ./emission.nix {
      inherit
        lib
        debugEnabled
        deploymentHostName
        containerName
        renderedModel
        firewallArg
        alarmModel
        ;
      uplinks = inputs.uplinks;
      wanUplinkName = inputs.wanUplinkName;
    };

  renderFlatContainers =
    containerModelsFlat:
    builtins.mapAttrs (
      containerName: model:
      emitContainer (
        if model ? deploymentHostName && builtins.isString model.deploymentHostName then
          model.deploymentHostName
        else
          inputs.defaultDeploymentHostName
      ) containerName model
    ) containerModelsFlat;

  renderNestedContainers =
    nestedModels:
    lib.mapAttrs (
      deploymentHostName: deploymentHostContainers:
      builtins.mapAttrs (
        containerName: model: emitContainer deploymentHostName containerName model
      ) deploymentHostContainers
    ) nestedModels;
in
if inputs.flatModels != null then
  renderFlatContainers inputs.flatModels
else if inputs.modelsByHost != null then
  renderNestedContainers inputs.modelsByHost
else
  { }
