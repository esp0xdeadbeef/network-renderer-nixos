{
  lib,
  controlPlaneOut,
  globalInventory,
  outPath,
  ...
}:

let
  hostname = "s-router-policy-only";
  inventory = globalInventory;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  fabricPath = "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  fabricImported =
    if builtins.pathExists fabricPath then
      import fabricPath
    else
      { };

  fabricInputs =
    if builtins.isFunction fabricImported then
      fabricImported { inherit lib; }
    else
      fabricImported;

  rootEnterprise =
    if controlPlaneOut ? control_plane_model
      && builtins.isAttrs controlPlaneOut.control_plane_model
      && controlPlaneOut.control_plane_model ? data
      && builtins.isAttrs controlPlaneOut.control_plane_model.data
    then
      controlPlaneOut.control_plane_model.data
    else
      abort "container/nftables.nix: control_plane_model.data missing";

  enterpriseNames = sortedAttrNames rootEnterprise;

  matchedSites =
    lib.concatMap (
      enterpriseName:
      let
        enterpriseValue = rootEnterprise.${enterpriseName};

        siteTree =
          if enterpriseValue ? site && builtins.isAttrs enterpriseValue.site then
            enterpriseValue.site
          else if builtins.isAttrs enterpriseValue then
            enterpriseValue
          else
            { };

        siteNames = sortedAttrNames siteTree;
      in
      lib.concatMap (
        siteName:
        let
          site = siteTree.${siteName};

          matchingPolicyTargets =
            if site ? policyTargets && builtins.isList site.policyTargets then
              lib.filter builtins.isString site.policyTargets
            else if site ? attachments && builtins.isList site.attachments then
              map (attachment: attachment.unit) (
                lib.filter (
                  attachment:
                    builtins.isAttrs attachment
                    && (attachment.kind or null) == "tenant"
                    && attachment ? unit
                    && builtins.isString attachment.unit
                ) site.attachments
              )
            else
              [ ];
        in
        lib.optionals (
          lib.elem hostname matchingPolicyTargets
          || hostname == "s-router-policy-only"
        ) [
          {
            inherit enterpriseName siteName site matchingPolicyTargets;
          }
        ]
      ) siteNames
    ) enterpriseNames;

  selectedSite =
    if builtins.length matchedSites == 1 then
      builtins.head matchedSites
    else if builtins.length matchedSites > 1 then
      abort ''
        container/nftables.nix: multiple policy sites matched hostname '${hostname}'
      ''
    else
      abort ''
        container/nftables.nix: no policy site matched hostname '${hostname}'
      '';

  cpmSite =
    if builtins.hasAttr selectedSite.enterpriseName rootEnterprise
      && builtins.isAttrs rootEnterprise.${selectedSite.enterpriseName}
      && builtins.hasAttr selectedSite.siteName rootEnterprise.${selectedSite.enterpriseName}
      && builtins.isAttrs rootEnterprise.${selectedSite.enterpriseName}.${selectedSite.siteName}
    then
      rootEnterprise.${selectedSite.enterpriseName}.${selectedSite.siteName}
    else if builtins.hasAttr selectedSite.enterpriseName rootEnterprise
      && builtins.isAttrs rootEnterprise.${selectedSite.enterpriseName}
      && rootEnterprise.${selectedSite.enterpriseName} ? site
      && builtins.isAttrs rootEnterprise.${selectedSite.enterpriseName}.site
      && builtins.hasAttr selectedSite.siteName rootEnterprise.${selectedSite.enterpriseName}.site
      && builtins.isAttrs rootEnterprise.${selectedSite.enterpriseName}.site.${selectedSite.siteName}
    then
      rootEnterprise.${selectedSite.enterpriseName}.site.${selectedSite.siteName}
    else if builtins.isAttrs selectedSite.site then
      selectedSite.site
    else
      abort ''
        container/nftables.nix: site '${selectedSite.siteName}' missing for enterprise '${selectedSite.enterpriseName}'
      '';

  intentEnterprise =
    if builtins.hasAttr selectedSite.enterpriseName fabricInputs
      && builtins.isAttrs fabricInputs.${selectedSite.enterpriseName}
    then
      fabricInputs.${selectedSite.enterpriseName}
    else
      { };

  intentSite =
    if builtins.hasAttr selectedSite.siteName intentEnterprise
      && builtins.isAttrs intentEnterprise.${selectedSite.siteName}
    then
      intentEnterprise.${selectedSite.siteName}
    else
      { };

  communicationContract =
    if cpmSite ? communicationContract && builtins.isAttrs cpmSite.communicationContract then
      cpmSite.communicationContract
    else if intentSite ? communicationContract && builtins.isAttrs intentSite.communicationContract then
      intentSite.communicationContract
    else
      abort "container/nftables.nix: communicationContract missing";

  ownership =
    if intentSite ? ownership && builtins.isAttrs intentSite.ownership then
      intentSite.ownership
    else
      { };

  ownershipEndpoints =
    if ownership ? endpoints && builtins.isList ownership.endpoints then
      lib.filter (
        endpoint:
          builtins.isAttrs endpoint
          && endpoint ? name
          && builtins.isString endpoint.name
          && endpoint ? tenant
          && builtins.isString endpoint.tenant
      ) ownership.endpoints
    else
      [ ];

  runtimeTargets =
    if cpmSite ? runtimeTargets && builtins.isAttrs cpmSite.runtimeTargets then
      cpmSite.runtimeTargets
    else
      { };

  runtimeTargetNames = sortedAttrNames runtimeTargets;

  policyRuntimeTargetCandidates =
    lib.filter (
      targetName:
      let
        target = runtimeTargets.${targetName};

        targetRole =
          if target ? role && builtins.isString target.role then
            target.role
          else
            null;

        logicalNodeName =
          if target ? logicalNode
            && builtins.isAttrs target.logicalNode
            && target.logicalNode ? name
            && builtins.isString target.logicalNode.name
          then
            target.logicalNode.name
          else
            null;

        placementHost =
          if target ? placement
            && builtins.isAttrs target.placement
            && target.placement ? host
            && builtins.isString target.placement.host
          then
            target.placement.host
          else
            null;
      in
      targetRole == "policy"
      || logicalNodeName == (cpmSite.policyNodeName or null)
      || targetName == hostname
      || placementHost == hostname
    ) runtimeTargetNames;

  policyRuntimeTargetName =
    if builtins.hasAttr hostname runtimeTargets then
      hostname
    else if builtins.length policyRuntimeTargetCandidates > 0 then
      builtins.head policyRuntimeTargetCandidates
    else
      abort "container/nftables.nix: no policy runtime target found";

  policyRuntimeTarget = runtimeTargets.${policyRuntimeTargetName};

  policyRuntimeInterfaces =
    if policyRuntimeTarget ? effectiveRuntimeRealization
      && builtins.isAttrs policyRuntimeTarget.effectiveRuntimeRealization
      && policyRuntimeTarget.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs policyRuntimeTarget.effectiveRuntimeRealization.interfaces
    then
      policyRuntimeTarget.effectiveRuntimeRealization.interfaces
    else
      abort "container/nftables.nix: policy runtime interfaces missing";

  policyRuntimeInterfaceNames = sortedAttrNames policyRuntimeInterfaces;

  actualIfNameFor =
    iface:
    if iface ? runtimeIfName && builtins.isString iface.runtimeIfName then
      iface.runtimeIfName
    else if iface ? renderedIfName && builtins.isString iface.renderedIfName then
      iface.renderedIfName
    else
      null;

  interfaceRefStrings =
    iface:
    let
      sourceInterface =
        if iface ? sourceInterface && builtins.isString iface.sourceInterface then
          iface.sourceInterface
        else
          "";

      backingRefName =
        if iface ? backingRef
          && builtins.isAttrs iface.backingRef
          && iface.backingRef ? name
          && builtins.isString iface.backingRef.name
        then
          iface.backingRef.name
        else
          "";

      runtimeIfName =
        if iface ? runtimeIfName && builtins.isString iface.runtimeIfName then
          iface.runtimeIfName
        else
          "";

      renderedIfName =
        if iface ? renderedIfName && builtins.isString iface.renderedIfName then
          iface.renderedIfName
        else
          "";
    in
    [
      sourceInterface
      backingRefName
      runtimeIfName
      renderedIfName
    ];

  tenantAttachments =
    if cpmSite ? attachments && builtins.isList cpmSite.attachments then
      lib.filter (
        attachment:
          builtins.isAttrs attachment
          && (attachment.kind or null) == "tenant"
          && attachment ? name
          && builtins.isString attachment.name
          && attachment ? unit
          && builtins.isString attachment.unit
      ) cpmSite.attachments
    else
      [ ];

  tenantInterfaceByName =
    builtins.listToAttrs (
      lib.filter (entry: entry != null) (
        map (
          attachment:
          let
            candidateIfNames =
              lib.filter (
                ifName:
                let
                  iface = policyRuntimeInterfaces.${ifName};
                in
                builtins.any (ref: lib.hasInfix attachment.unit ref) (interfaceRefStrings iface)
              ) policyRuntimeInterfaceNames;

            selectedIfName =
              if builtins.length candidateIfNames > 0 then
                actualIfNameFor policyRuntimeInterfaces.${builtins.head candidateIfNames}
              else
                null;
          in
          if selectedIfName != null then
            {
              name = attachment.name;
              value = selectedIfName;
            }
          else
            null
        ) tenantAttachments
      )
    );

  upstreamInterfaceCandidates =
    lib.filter (
      ifName:
      let
        iface = policyRuntimeInterfaces.${ifName};
      in
      builtins.any (
        ref:
          lib.hasInfix (cpmSite.upstreamSelectorNodeName or "s-router-upstream-selector") ref
          || ref == "upstream"
      ) (interfaceRefStrings iface)
    ) policyRuntimeInterfaceNames;

  upstreamInterfaceName =
    if builtins.length upstreamInterfaceCandidates > 0 then
      actualIfNameFor policyRuntimeInterfaces.${builtins.head upstreamInterfaceCandidates}
    else
      null;

  serviceDefinitions =
    if communicationContract ? services && builtins.isList communicationContract.services then
      lib.filter (
        service:
          builtins.isAttrs service
          && service ? name
          && builtins.isString service.name
      ) communicationContract.services
    else
      [ ];

  providerTenantFor =
    providerName:
    let
      matches =
        lib.filter (
          endpoint:
            endpoint.name == providerName
        ) ownershipEndpoints;
    in
    if builtins.length matches > 0 then
      (builtins.head matches).tenant
    else
      null;

  serviceInterfacesByName =
    builtins.listToAttrs (
      map (
        service:
        let
          providers =
            if service ? providers && builtins.isList service.providers then
              lib.filter builtins.isString service.providers
            else
              [ ];

          providerTenants =
            lib.filter (tenant: tenant != null) (map providerTenantFor providers);

          interfaces =
            lib.unique (
              lib.filter (iface: iface != null) (
                map (
                  tenant:
                    if builtins.hasAttr tenant tenantInterfaceByName then
                      tenantInterfaceByName.${tenant}
                    else
                      null
                ) providerTenants
              )
            );
        in
        {
          name = service.name;
          value = interfaces;
        }
      ) serviceDefinitions
    );

  interfaceTags =
    if communicationContract ? interfaceTags && builtins.isAttrs communicationContract.interfaceTags then
      communicationContract.interfaceTags
    else
      { };

  normalizeToken =
    token:
    if builtins.hasAttr token interfaceTags && builtins.isString interfaceTags.${token} then
      interfaceTags.${token}
    else
      token;

  allKnownInterfaces =
    lib.unique (
      (builtins.attrValues tenantInterfaceByName)
      ++ lib.optionals (upstreamInterfaceName != null) [ upstreamInterfaceName ]
    );

  resolveEndpoint =
    endpoint:
    if endpoint == "any" then
      allKnownInterfaces
    else if builtins.isString endpoint then
      let
        token = normalizeToken endpoint;
      in
      if token == "any" then
        allKnownInterfaces
      else if token == "wan" || token == "external-wan" || token == "upstream" then
        lib.optionals (upstreamInterfaceName != null) [ upstreamInterfaceName ]
      else if builtins.hasAttr token tenantInterfaceByName then
        [ tenantInterfaceByName.${token} ]
      else if builtins.hasAttr token serviceInterfacesByName then
        serviceInterfacesByName.${token}
      else
        [ ]
    else if builtins.isAttrs endpoint then
      let
        kind = endpoint.kind or null;
      in
      if kind == "tenant" && endpoint ? name && builtins.hasAttr endpoint.name tenantInterfaceByName then
        [ tenantInterfaceByName.${endpoint.name} ]
      else if kind == "tenant-set" && endpoint ? members && builtins.isList endpoint.members then
        lib.unique (
          lib.concatMap (
            member:
              if builtins.isString member && builtins.hasAttr member tenantInterfaceByName then
                [ tenantInterfaceByName.${member} ]
              else
                [ ]
          ) endpoint.members
        )
      else if kind == "external" && (endpoint.name or null) == "wan" then
        lib.optionals (upstreamInterfaceName != null) [ upstreamInterfaceName ]
      else if kind == "service" && endpoint ? name && builtins.hasAttr endpoint.name serviceInterfacesByName then
        serviceInterfacesByName.${endpoint.name}
      else
        [ ]
    else
      [ ];

  trafficTypeDefinitions =
    if communicationContract ? trafficTypes && builtins.isList communicationContract.trafficTypes then
      builtins.listToAttrs (
        map (
          trafficType:
          {
            name = trafficType.name;
            value = trafficType;
          }
        ) (
          lib.filter (
            trafficType:
              builtins.isAttrs trafficType
              && trafficType ? name
              && builtins.isString trafficType.name
          ) communicationContract.trafficTypes
        )
      )
    else
      { };

  renderMatch =
    match:
    let
      family =
        if match ? family && builtins.isString match.family then
          match.family
        else
          "any";

      proto =
        if match ? proto && builtins.isString match.proto then
          match.proto
        else
          null;

      dports =
        if match ? dports && builtins.isList match.dports then
          lib.filter builtins.isInt match.dports
        else
          [ ];

      portExpr =
        if dports == [ ] then
          ""
        else
          " ${proto} dport { ${builtins.concatStringsSep ", " (map toString dports)} }";

      familyPrefix =
        if family == "ipv4" then
          "meta nfproto ipv4 "
        else if family == "ipv6" then
          "meta nfproto ipv6 "
        else
          "";
    in
    if proto == null then
      [ "" ]
    else if proto == "icmp" then
      if family == "ipv4" then
        [ "meta nfproto ipv4 ip protocol icmp" ]
      else if family == "ipv6" then
        [ "meta nfproto ipv6 ip6 nexthdr ipv6-icmp" ]
      else
        [
          "meta nfproto ipv4 ip protocol icmp"
          "meta nfproto ipv6 ip6 nexthdr ipv6-icmp"
        ]
    else if proto == "tcp" || proto == "udp" then
      [ "${familyPrefix}meta l4proto ${proto}${portExpr}" ]
    else
      [ "${familyPrefix}meta l4proto ${proto}" ];

  renderTrafficType =
    trafficTypeName:
    if trafficTypeName == null || trafficTypeName == "any" then
      [ "" ]
    else if builtins.hasAttr trafficTypeName trafficTypeDefinitions then
      let
        trafficType = trafficTypeDefinitions.${trafficTypeName};

        matches =
          if trafficType ? match && builtins.isList trafficType.match then
            trafficType.match
          else
            [ ];
      in
      if matches == [ ] then
        [ "" ]
      else
        lib.concatMap renderMatch matches
    else
      [ "" ];

  relations =
    if communicationContract ? relations && builtins.isList communicationContract.relations then
      lib.sort (
        a: b:
          let
            pa =
              if a ? priority && builtins.isInt a.priority then
                a.priority
              else
                1000;
            pb =
              if b ? priority && builtins.isInt b.priority then
                b.priority
              else
                1000;
          in
          pa < pb
      ) (
        lib.filter builtins.isAttrs communicationContract.relations
      )
    else
      [ ];

  renderedRules =
    lib.unique (
      lib.concatMap (
        relation:
        let
          action =
            if (relation.action or "allow") == "deny" then
              "drop"
            else
              "accept";

          fromEndpoints =
            resolveEndpoint (
              if relation ? from then
                relation.from
              else
                [ ]
            );

          toEndpoints =
            resolveEndpoint (
              if relation ? to then
                relation.to
              else
                [ ]
            );

          trafficMatches =
            renderTrafficType (
              if relation ? trafficType && builtins.isString relation.trafficType then
                relation.trafficType
              else
                null
            );

          commentText =
            if relation ? id && builtins.isString relation.id then
              " comment \"${relation.id}\""
            else
              "";
        in
        lib.concatMap (
          fromIf:
          lib.concatMap (
            toIf:
            map (
              matchExpr:
              let
                matchPart =
                  if matchExpr == "" then
                    ""
                  else
                    " ${matchExpr}";
              in
              "        iifname \"${fromIf}\" oifname \"${toIf}\"${matchPart} ${action}${commentText}"
            ) trafficMatches
          ) toEndpoints
        ) fromEndpoints
      ) relations
    );

  rulesetText = ''
    table inet edge_policy {
      chain input {
        type filter hook input priority filter; policy accept;
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state invalid drop
        ct state established,related accept
${builtins.concatStringsSep "\n" renderedRules}
      }

      chain output {
        type filter hook output priority filter; policy accept;
      }
    }
  '';
in
{
  networking.nftables = {
    enable = true;
    ruleset = rulesetText;
  };
}
