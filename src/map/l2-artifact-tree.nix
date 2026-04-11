{ lib }:
{ normalizedModel }:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureList =
    name: value:
    if builtins.isList value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a list";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  ensureInt =
    name: value:
    if builtins.isInt value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an integer";

  json = value: builtins.toJSON value;

  validPathSegment =
    name: value:
    let
      s = toString value;
    in
    if s == "" then
      throw "network-renderer-nixos: ${name} must not be empty"
    else if s == "." || s == ".." then
      throw "network-renderer-nixos: ${name} '${s}' is not a valid artifact path segment"
    else if lib.hasInfix "/" s then
      throw "network-renderer-nixos: ${name} '${s}' must not contain '/'"
    else
      s;

  normalizeOptionalString = name: value: if value == null then null else ensureString name value;

  normalizeOptionalAttrs = name: value: if value == null then null else ensureAttrs name value;

  normalizeVlanProfileCandidate =
    name: value:
    if value == null then
      null
    else if builtins.isInt value then
      { vlanId = value; }
    else if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an integer or attribute set";

  uniqueById =
    label: items:
    let
      byId = builtins.foldl' (
        acc: item:
        let
          itemDef = ensureAttrs "${label} entry" item;
          id = ensureString "${label} entry.id" itemDef.id;
        in
        if builtins.hasAttr id acc then
          if json acc.${id} == json itemDef then
            acc
          else
            throw "network-renderer-nixos: ${label} '${id}' is defined multiple times with different values"
        else
          acc // { "${id}" = itemDef; }
      ) { } items;
    in
    map (id: byId.${id}) (sortedAttrNames byId);

  jsonFileEntry = name: value: {
    inherit name;
    value = {
      format = "json";
      inherit value;
    };
  };

  emptyCollected = {
    bridges = [ ];
    hostAdapters = [ ];
    containerAdapters = [ ];
    adapterPairings = [ ];
    bridgeMemberships = [ ];
    vlanProfiles = [ ];
    l2AttachmentPolicies = [ ];
    deviceCreationSteps = [ ];
  };

  mergeCollected = left: right: {
    bridges = left.bridges ++ right.bridges;
    hostAdapters = left.hostAdapters ++ right.hostAdapters;
    containerAdapters = left.containerAdapters ++ right.containerAdapters;
    adapterPairings = left.adapterPairings ++ right.adapterPairings;
    bridgeMemberships = left.bridgeMemberships ++ right.bridgeMemberships;
    vlanProfiles = left.vlanProfiles ++ right.vlanProfiles;
    l2AttachmentPolicies = left.l2AttachmentPolicies ++ right.l2AttachmentPolicies;
    deviceCreationSteps = left.deviceCreationSteps ++ right.deviceCreationSteps;
  };

  siteData = ensureAttrs "control_plane_model.data" normalizedModel.siteData;

  _haveSiteData =
    if siteData == { } then
      throw "network-renderer-nixos: control-plane output is missing control_plane_model.data"
    else
      true;

  runtimeTargetsForSite =
    enterpriseName: siteName: site:
    if site ? runtimeTargets then
      ensureAttrs "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets" site.runtimeTargets
    else
      { };

  hostNameForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    if !(runtimeTarget ? placement) || !(builtins.isAttrs runtimeTarget.placement) then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing placement"
    else if
      !(runtimeTarget.placement ? host)
      || !(builtins.isString runtimeTarget.placement.host)
      || runtimeTarget.placement.host == ""
    then
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing placement.host"
    else
      validPathSegment "host name for runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" runtimeTarget.placement.host;

  containerNamesForRuntimeTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    let
      containerNames =
        if runtimeTarget ? containers then
          map
            (
              containerName:
              validPathSegment "container name for runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" containerName
            )
            (
              ensureList "control_plane_model.data.${enterpriseName}.${siteName}.runtimeTargets.${runtimeTargetName}.containers" runtimeTarget.containers
            )
        else
          [ ];

      uniqueContainerNames = lib.unique containerNames;

      _uniqueContainerNames =
        if builtins.length containerNames == builtins.length uniqueContainerNames then
          true
        else
          throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' defines duplicate container names";
    in
    builtins.seq _uniqueContainerNames uniqueContainerNames;

  runtimeInterfacesForTarget =
    enterpriseName: siteName: runtimeTargetName: runtimeTarget:
    if
      runtimeTarget ? effectiveRuntimeRealization
      && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization
      && runtimeTarget.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs runtimeTarget.effectiveRuntimeRealization.interfaces
    then
      runtimeTarget.effectiveRuntimeRealization.interfaces
    else
      throw "network-renderer-nixos: runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing effectiveRuntimeRealization.interfaces";

  runtimeIfNameForInterface =
    enterpriseName: siteName: runtimeTargetName: interfaceName: interface:
    if
      interface ? runtimeIfName
      && builtins.isString interface.runtimeIfName
      && interface.runtimeIfName != ""
    then
      interface.runtimeIfName
    else if
      interface ? renderedIfName
      && builtins.isString interface.renderedIfName
      && interface.renderedIfName != ""
    then
      interface.renderedIfName
    else
      throw "network-renderer-nixos: interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing runtimeIfName/renderedIfName";

  logicalNodeNameForRuntimeTarget =
    runtimeTarget:
    if
      runtimeTarget ? logicalNode
      && builtins.isAttrs runtimeTarget.logicalNode
      && runtimeTarget.logicalNode ? name
      && builtins.isString runtimeTarget.logicalNode.name
      && runtimeTarget.logicalNode.name != ""
    then
      runtimeTarget.logicalNode.name
    else
      null;

  hashFragment = value: builtins.substring 0 11 (builtins.hashString "sha256" value);

  hostPairIfName =
    hostName: containerName: runtimeTargetName: runtimeIfName:
    "vh-${hashFragment "${hostName}:${containerName}:${runtimeTargetName}:${runtimeIfName}"}";

  resolveHostUplink =
    enterpriseName: siteName: runtimeTargetName: interfaceName: interface:
    if interface ? hostUplink then
      ensureAttrs "host uplink for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" interface.hostUplink
    else
      null;

  resolveHostUplinkName =
    enterpriseName: siteName: runtimeTargetName: interfaceName: hostUplink:
    if hostUplink == null then
      null
    else if hostUplink ? name then
      ensureString "host uplink name for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" hostUplink.name
    else
      throw "network-renderer-nixos: interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' is missing hostUplink.name";

  resolveBridgeName =
    enterpriseName: siteName: runtimeTargetName: interfaceName: hostUplink:
    if hostUplink == null then
      null
    else if hostUplink ? bridge then
      ensureString "host uplink bridge for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" hostUplink.bridge
    else
      null;

  resolveVlanProfile =
    enterpriseName: siteName: runtimeTargetName: interfaceName: interface: hostUplink:
    let
      candidates = lib.filter (value: value != null) [
        (
          if interface ? vlanProfile then
            normalizeVlanProfileCandidate "vlanProfile for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" interface.vlanProfile
          else
            null
        )
        (
          if interface ? vlan then
            normalizeVlanProfileCandidate "vlan for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" interface.vlan
          else
            null
        )
        (
          if hostUplink != null && hostUplink ? vlanProfile then
            normalizeVlanProfileCandidate "hostUplink.vlanProfile for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" hostUplink.vlanProfile
          else
            null
        )
        (
          if hostUplink != null && hostUplink ? vlan then
            normalizeVlanProfileCandidate "hostUplink.vlan for interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}'" hostUplink.vlan
          else
            null
        )
      ];

      distinctCandidates = lib.unique (map json candidates);
    in
    if candidates == [ ] then
      null
    else if builtins.length distinctCandidates == 1 then
      builtins.head candidates
    else
      throw "network-renderer-nixos: interface '${interfaceName}' on runtime target '${runtimeTargetName}' in '${enterpriseName}.${siteName}' defines conflicting VLAN profiles";

  vlanProfileIdFor =
    profile: "vlan-profile::${builtins.substring 0 12 (builtins.hashString "sha256" (json profile))}";

  bridgeEntry = hostName: bridgeName: {
    id = "bridge::${hostName}::${bridgeName}";
    host = hostName;
    bridgeName = bridgeName;
  };

  hostUplinkAdapterEntry = hostName: runtimeTargetName: runtimeIfName: hostUplinkName: {
    id = "host-uplink::${hostName}::${hostUplinkName}";
    host = hostName;
    kind = "host-uplink";
    hostInterfaceName = hostUplinkName;
    runtimeTargetName = runtimeTargetName;
    runtimeInterfaceName = runtimeIfName;
  };

  hostRuntimeAdapterEntry =
    {
      hostName,
      runtimeTargetName,
      logicalNodeName,
      runtimeIfName,
      interface,
      attachmentPolicyId,
    }:
    {
      id = "host-runtime::${hostName}::${runtimeTargetName}::${runtimeIfName}";
      host = hostName;
      kind = "host-runtime-interface";
      hostInterfaceName = runtimeIfName;
      runtimeTargetName = runtimeTargetName;
      logicalNodeName = logicalNodeName;
      runtimeInterfaceName = runtimeIfName;
      sourceKind = normalizeOptionalString "host runtime adapter sourceKind" (
        interface.sourceKind or null
      );
      sourceInterface = normalizeOptionalString "host runtime adapter sourceInterface" (
        interface.sourceInterface or null
      );
      backingRef = normalizeOptionalAttrs "host runtime adapter backingRef" (
        interface.backingRef or null
      );
      address4 = normalizeOptionalString "host runtime adapter addr4" (interface.addr4 or null);
      address6 = normalizeOptionalString "host runtime adapter addr6" (interface.addr6 or null);
      attachmentPolicyId = attachmentPolicyId;
    };

  hostPairAdapterEntry =
    {
      hostName,
      containerName,
      runtimeTargetName,
      logicalNodeName,
      runtimeIfName,
      hostInterfaceName,
      interface,
      attachmentPolicyId,
    }:
    {
      id = "host-pair::${hostName}::${containerName}::${runtimeTargetName}::${runtimeIfName}";
      host = hostName;
      container = containerName;
      kind = "host-pair-end";
      hostInterfaceName = hostInterfaceName;
      runtimeTargetName = runtimeTargetName;
      logicalNodeName = logicalNodeName;
      runtimeInterfaceName = runtimeIfName;
      sourceKind = normalizeOptionalString "host pair adapter sourceKind" (interface.sourceKind or null);
      sourceInterface = normalizeOptionalString "host pair adapter sourceInterface" (
        interface.sourceInterface or null
      );
      backingRef = normalizeOptionalAttrs "host pair adapter backingRef" (interface.backingRef or null);
      address4 = normalizeOptionalString "host pair adapter addr4" (interface.addr4 or null);
      address6 = normalizeOptionalString "host pair adapter addr6" (interface.addr6 or null);
      attachmentPolicyId = attachmentPolicyId;
    };

  containerAdapterEntry =
    {
      hostName,
      containerName,
      runtimeTargetName,
      logicalNodeName,
      runtimeIfName,
      interface,
      attachmentPolicyId,
    }:
    {
      id = "container-adapter::${hostName}::${containerName}::${runtimeTargetName}::${runtimeIfName}";
      host = hostName;
      container = containerName;
      kind = "container-runtime-interface";
      containerInterfaceName = runtimeIfName;
      runtimeTargetName = runtimeTargetName;
      logicalNodeName = logicalNodeName;
      runtimeInterfaceName = runtimeIfName;
      sourceKind = normalizeOptionalString "container adapter sourceKind" (interface.sourceKind or null);
      sourceInterface = normalizeOptionalString "container adapter sourceInterface" (
        interface.sourceInterface or null
      );
      backingRef = normalizeOptionalAttrs "container adapter backingRef" (interface.backingRef or null);
      address4 = normalizeOptionalString "container adapter addr4" (interface.addr4 or null);
      address6 = normalizeOptionalString "container adapter addr6" (interface.addr6 or null);
      attachmentPolicyId = attachmentPolicyId;
    };

  attachmentPolicyEntry =
    {
      hostName,
      containerName ? null,
      runtimeTargetName,
      logicalNodeName,
      runtimeIfName,
      sourceKind,
      hostAdapterId,
      containerAdapterId ? null,
      attachmentKind,
      bridgeName ? null,
      vlanProfileId ? null,
    }:
    {
      id =
        "l2-attachment::${hostName}::${runtimeTargetName}::${runtimeIfName}"
        + (if containerName == null then "" else "::${containerName}");
      host = hostName;
      container = containerName;
      runtimeTargetName = runtimeTargetName;
      logicalNodeName = logicalNodeName;
      runtimeInterfaceName = runtimeIfName;
      sourceKind = sourceKind;
      hostAdapterId = hostAdapterId;
      containerAdapterId = containerAdapterId;
      attachmentKind = attachmentKind;
      bridgeName = bridgeName;
      vlanProfileId = vlanProfileId;
    };

  pairingEntry =
    {
      hostName,
      containerName,
      runtimeTargetName,
      runtimeIfName,
      hostAdapterId,
      hostInterfaceName,
      containerAdapterId,
    }:
    {
      id = "adapter-pairing::${hostAdapterId}::${containerAdapterId}";
      host = hostName;
      container = containerName;
      runtimeTargetName = runtimeTargetName;
      runtimeInterfaceName = runtimeIfName;
      hostAdapterId = hostAdapterId;
      hostInterfaceName = hostInterfaceName;
      containerAdapterId = containerAdapterId;
      containerInterfaceName = runtimeIfName;
      pairingKind = "veth";
    };

  bridgeMembershipEntry =
    {
      hostName,
      bridgeName,
      adapterId,
      hostInterfaceName,
      adapterKind,
      vlanProfileId ? null,
    }:
    {
      id = "bridge-membership::${hostName}::${bridgeName}::${adapterId}";
      host = hostName;
      bridgeName = bridgeName;
      adapterId = adapterId;
      hostInterfaceName = hostInterfaceName;
      adapterKind = adapterKind;
      attachmentKind = "bridge";
      vlanProfileId = vlanProfileId;
    };

  vlanProfileEntry = hostName: bridgeName: profileId: profile: {
    id = profileId;
    host = hostName;
    bridgeName = bridgeName;
    profile = profile;
  };

  deviceStep =
    id: phase: value:
    {
      inherit id phase;
    }
    // value;

  collectInterfaceArtifacts =
    {
      enterpriseName,
      siteName,
      hostName,
      runtimeTargetName,
      runtimeTarget,
      containerNames,
      interfaceName,
      interface,
    }:
    let
      runtimeIfName =
        runtimeIfNameForInterface enterpriseName siteName runtimeTargetName interfaceName
          interface;

      logicalNodeName = logicalNodeNameForRuntimeTarget runtimeTarget;

      sourceKind = normalizeOptionalString "sourceKind" (interface.sourceKind or null);

      hostUplink = resolveHostUplink enterpriseName siteName runtimeTargetName interfaceName interface;

      hostUplinkName =
        resolveHostUplinkName enterpriseName siteName runtimeTargetName interfaceName
          hostUplink;

      bridgeName = resolveBridgeName enterpriseName siteName runtimeTargetName interfaceName hostUplink;

      attachmentKind = if bridgeName == null then "direct" else "bridge";

      vlanProfile =
        resolveVlanProfile enterpriseName siteName runtimeTargetName interfaceName interface
          hostUplink;

      vlanProfileId = if vlanProfile == null then null else vlanProfileIdFor vlanProfile;

      uplinkAdapterId =
        if hostUplinkName == null then null else "host-uplink::${hostName}::${hostUplinkName}";

      baseInfra =
        mergeCollected
          (
            if bridgeName == null then
              emptyCollected
            else
              {
                bridges = [ (bridgeEntry hostName bridgeName) ];
                hostAdapters = [ ];
                containerAdapters = [ ];
                adapterPairings = [ ];
                bridgeMemberships = [ ];
                vlanProfiles = [ ];
                l2AttachmentPolicies = [ ];
                deviceCreationSteps = [
                  (deviceStep "step::bridge::${hostName}::${bridgeName}" 10 {
                    kind = "bridge";
                    host = hostName;
                    bridgeName = bridgeName;
                  })
                ];
              }
          )
          (
            if hostUplinkName == null then
              emptyCollected
            else
              {
                bridges = [ ];
                hostAdapters = [
                  (hostUplinkAdapterEntry hostName runtimeTargetName runtimeIfName hostUplinkName)
                ];
                containerAdapters = [ ];
                adapterPairings = [ ];
                bridgeMemberships =
                  if bridgeName == null then
                    [ ]
                  else
                    [
                      (bridgeMembershipEntry {
                        inherit hostName bridgeName;
                        adapterId = uplinkAdapterId;
                        hostInterfaceName = hostUplinkName;
                        adapterKind = "host-uplink";
                        vlanProfileId = vlanProfileId;
                      })
                    ];
                vlanProfiles =
                  if vlanProfile == null then
                    [ ]
                  else
                    [
                      (vlanProfileEntry hostName bridgeName vlanProfileId vlanProfile)
                    ];
                l2AttachmentPolicies = [ ];
                deviceCreationSteps = [
                  (deviceStep "step::host-uplink::${hostName}::${hostUplinkName}" 20 {
                    kind = "host-uplink";
                    host = hostName;
                    hostAdapterId = uplinkAdapterId;
                    hostInterfaceName = hostUplinkName;
                  })
                ]
                ++ (
                  if bridgeName == null then
                    [ ]
                  else
                    [
                      (deviceStep "step::bridge-membership::${hostName}::${bridgeName}::${uplinkAdapterId}" 60 {
                        kind = "bridge-membership";
                        host = hostName;
                        bridgeName = bridgeName;
                        adapterId = uplinkAdapterId;
                        hostInterfaceName = hostUplinkName;
                      })
                    ]
                );
              }
          );

      hostScopedArtifacts =
        let
          policy = attachmentPolicyEntry {
            inherit
              hostName
              runtimeTargetName
              logicalNodeName
              runtimeIfName
              sourceKind
              attachmentKind
              bridgeName
              vlanProfileId
              ;
            hostAdapterId = "host-runtime::${hostName}::${runtimeTargetName}::${runtimeIfName}";
          };

          hostAdapter = hostRuntimeAdapterEntry {
            inherit
              hostName
              runtimeTargetName
              logicalNodeName
              runtimeIfName
              interface
              ;
            attachmentPolicyId = policy.id;
          };
        in
        {
          bridges = [ ];
          hostAdapters = [ hostAdapter ];
          containerAdapters = [ ];
          adapterPairings = [ ];
          bridgeMemberships =
            if bridgeName == null then
              [ ]
            else
              [
                (bridgeMembershipEntry {
                  inherit hostName bridgeName vlanProfileId;
                  adapterId = hostAdapter.id;
                  hostInterfaceName = hostAdapter.hostInterfaceName;
                  adapterKind = hostAdapter.kind;
                })
              ];
          vlanProfiles =
            if vlanProfile == null then
              [ ]
            else
              [ (vlanProfileEntry hostName bridgeName vlanProfileId vlanProfile) ];
          l2AttachmentPolicies = [ policy ];
          deviceCreationSteps = [
            (deviceStep "step::host-runtime::${hostAdapter.id}" 30 {
              kind = "host-runtime-interface";
              host = hostName;
              hostAdapterId = hostAdapter.id;
              hostInterfaceName = hostAdapter.hostInterfaceName;
            })
          ]
          ++ (
            if bridgeName == null then
              [ ]
            else
              [
                (deviceStep "step::bridge-membership::${hostName}::${bridgeName}::${hostAdapter.id}" 60 {
                  kind = "bridge-membership";
                  host = hostName;
                  bridgeName = bridgeName;
                  adapterId = hostAdapter.id;
                  hostInterfaceName = hostAdapter.hostInterfaceName;
                })
              ]
          );
        };

      containerScopedArtifacts = builtins.foldl' (
        acc: containerName:
        let
          policy = attachmentPolicyEntry {
            inherit
              hostName
              containerName
              runtimeTargetName
              logicalNodeName
              runtimeIfName
              sourceKind
              attachmentKind
              bridgeName
              vlanProfileId
              ;
            hostAdapterId = "host-pair::${hostName}::${containerName}::${runtimeTargetName}::${runtimeIfName}";
            containerAdapterId = "container-adapter::${hostName}::${containerName}::${runtimeTargetName}::${runtimeIfName}";
          };

          plannedHostIfName = hostPairIfName hostName containerName runtimeTargetName runtimeIfName;

          hostAdapter = hostPairAdapterEntry {
            inherit
              hostName
              containerName
              runtimeTargetName
              logicalNodeName
              runtimeIfName
              interface
              ;
            hostInterfaceName = plannedHostIfName;
            attachmentPolicyId = policy.id;
          };

          containerAdapter = containerAdapterEntry {
            inherit
              hostName
              containerName
              runtimeTargetName
              logicalNodeName
              runtimeIfName
              interface
              ;
            attachmentPolicyId = policy.id;
          };

          pairing = pairingEntry {
            inherit
              hostName
              containerName
              runtimeTargetName
              runtimeIfName
              ;
            hostAdapterId = hostAdapter.id;
            hostInterfaceName = plannedHostIfName;
            containerAdapterId = containerAdapter.id;
          };
        in
        mergeCollected acc {
          bridges = [ ];
          hostAdapters = [ hostAdapter ];
          containerAdapters = [ containerAdapter ];
          adapterPairings = [ pairing ];
          bridgeMemberships =
            if bridgeName == null then
              [ ]
            else
              [
                (bridgeMembershipEntry {
                  inherit hostName bridgeName vlanProfileId;
                  adapterId = hostAdapter.id;
                  hostInterfaceName = plannedHostIfName;
                  adapterKind = hostAdapter.kind;
                })
              ];
          vlanProfiles =
            if vlanProfile == null then
              [ ]
            else
              [ (vlanProfileEntry hostName bridgeName vlanProfileId vlanProfile) ];
          l2AttachmentPolicies = [ policy ];
          deviceCreationSteps = [
            (deviceStep "step::host-pair::${hostAdapter.id}" 30 {
              kind = "host-pair-end";
              host = hostName;
              hostAdapterId = hostAdapter.id;
              hostInterfaceName = plannedHostIfName;
            })
            (deviceStep "step::container-adapter::${containerAdapter.id}" 40 {
              kind = "container-adapter";
              host = hostName;
              container = containerName;
              containerAdapterId = containerAdapter.id;
              containerInterfaceName = containerAdapter.containerInterfaceName;
            })
            (deviceStep "step::pairing::${pairing.id}" 50 {
              kind = "adapter-pairing";
              host = hostName;
              container = containerName;
              pairingId = pairing.id;
              hostAdapterId = hostAdapter.id;
              containerAdapterId = containerAdapter.id;
            })
          ]
          ++ (
            if bridgeName == null then
              [ ]
            else
              [
                (deviceStep "step::bridge-membership::${hostName}::${bridgeName}::${hostAdapter.id}" 60 {
                  kind = "bridge-membership";
                  host = hostName;
                  bridgeName = bridgeName;
                  adapterId = hostAdapter.id;
                  hostInterfaceName = plannedHostIfName;
                })
              ]
          );
        }
      ) emptyCollected containerNames;
    in
    mergeCollected baseInfra (
      if containerNames == [ ] then hostScopedArtifacts else containerScopedArtifacts
    );

  groupRuntimeTargetsByHost =
    enterpriseName: siteName: runtimeTargets:
    builtins.foldl' (
      acc: runtimeTargetName:
      let
        runtimeTarget = runtimeTargets.${runtimeTargetName};
        hostName = hostNameForRuntimeTarget enterpriseName siteName runtimeTargetName runtimeTarget;
      in
      acc
      // {
        "${hostName}" = (acc.${hostName} or { }) // {
          "${runtimeTargetName}" = runtimeTarget;
        };
      }
    ) { } (sortedAttrNames runtimeTargets);

  hostArtifactFilesForSite =
    enterpriseName: siteName: runtimeTargets:
    let
      runtimeTargetsByHost = groupRuntimeTargetsByHost enterpriseName siteName runtimeTargets;
    in
    lib.concatMap (
      hostName:
      let
        hostSegment = validPathSegment "host name" hostName;
        hostPath = "${validPathSegment "enterprise name" enterpriseName}/${validPathSegment "site name" siteName}/${hostSegment}";

        hostRuntimeTargets = runtimeTargetsByHost.${hostName};

        collected = builtins.foldl' (
          acc: runtimeTargetName:
          let
            runtimeTarget = hostRuntimeTargets.${runtimeTargetName};
            containerNames =
              containerNamesForRuntimeTarget enterpriseName siteName runtimeTargetName
                runtimeTarget;
            interfaces = runtimeInterfacesForTarget enterpriseName siteName runtimeTargetName runtimeTarget;
          in
          builtins.foldl' (
            innerAcc: interfaceName:
            mergeCollected innerAcc (collectInterfaceArtifacts {
              inherit
                enterpriseName
                siteName
                hostName
                runtimeTargetName
                runtimeTarget
                containerNames
                interfaceName
                ;
              interface = interfaces.${interfaceName};
            })
          ) acc (sortedAttrNames interfaces)
        ) emptyCollected (sortedAttrNames hostRuntimeTargets);

        bridges = uniqueById "host bridge" collected.bridges;
        hostAdapters = uniqueById "host adapter" collected.hostAdapters;
        containerAdapters = uniqueById "container adapter" collected.containerAdapters;
        adapterPairings = uniqueById "adapter pairing" collected.adapterPairings;
        bridgeMemberships = uniqueById "bridge membership" collected.bridgeMemberships;
        vlanProfiles = uniqueById "VLAN profile" collected.vlanProfiles;
        l2AttachmentPolicies = uniqueById "L2 attachment policy" collected.l2AttachmentPolicies;

        deviceCreationSteps = lib.sort (
          left: right:
          let
            leftPhase = ensureInt "device creation step phase" left.phase;
            rightPhase = ensureInt "device creation step phase" right.phase;
            leftId = ensureString "device creation step id" left.id;
            rightId = ensureString "device creation step id" right.id;
          in
          if leftPhase == rightPhase then leftId < rightId else leftPhase < rightPhase
        ) (uniqueById "device creation step" collected.deviceCreationSteps);
      in
      [
        (jsonFileEntry "${hostPath}/l2/bridges.json" {
          host = hostName;
          bridges = bridges;
        })
        (jsonFileEntry "${hostPath}/l2/host-adapters.json" {
          host = hostName;
          adapters = hostAdapters;
        })
        (jsonFileEntry "${hostPath}/l2/container-adapters.json" {
          host = hostName;
          adapters = containerAdapters;
        })
        (jsonFileEntry "${hostPath}/l2/adapter-pairings.json" {
          host = hostName;
          pairings = adapterPairings;
        })
        (jsonFileEntry "${hostPath}/l2/bridge-memberships.json" {
          host = hostName;
          memberships = bridgeMemberships;
        })
        (jsonFileEntry "${hostPath}/l2/vlan-profiles.json" {
          host = hostName;
          profiles = vlanProfiles;
        })
        (jsonFileEntry "${hostPath}/l2/l2-attachment-policy.json" {
          host = hostName;
          policies = l2AttachmentPolicies;
        })
        (jsonFileEntry "${hostPath}/l2/device-creation-order.json" {
          host = hostName;
          steps = deviceCreationSteps;
        })
      ]
    ) (sortedAttrNames runtimeTargetsByHost);

  fileEntries = lib.concatMap (
    enterpriseName:
    let
      enterpriseSites =
        ensureAttrs "control_plane_model.data.${enterpriseName}"
          siteData.${enterpriseName};
    in
    lib.concatMap (
      siteName:
      let
        site =
          ensureAttrs "control_plane_model.data.${enterpriseName}.${siteName}"
            enterpriseSites.${siteName};
        runtimeTargets = runtimeTargetsForSite enterpriseName siteName site;
      in
      hostArtifactFilesForSite enterpriseName siteName runtimeTargets
    ) (sortedAttrNames enterpriseSites)
  ) (sortedAttrNames siteData);

  filePaths = map (entry: entry.name) fileEntries;

  _uniquePaths =
    if builtins.length filePaths == builtins.length (lib.unique filePaths) then
      true
    else
      throw "network-renderer-nixos: L2 artifact file mapping produced duplicate paths";
in
builtins.seq _haveSiteData (builtins.seq _uniquePaths (builtins.listToAttrs fileEntries))
