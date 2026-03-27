{
  lib,
  controlPlaneOut,
  globalInventory,
  outPath,
  runtimeUnitName,
  ...
}:

let
  inventory = globalInventory;

  runtimeContext = import "${outPath}/lib/runtime-context.nix" { inherit lib; };

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

  selectedSiteEntry = runtimeContext.siteEntryForUnit {
    cpm = controlPlaneOut;
    unitName = runtimeUnitName;
    file = "s88/Unit/s-router-policy-only/container/nftables.nix";
  };

  cpmSite = selectedSiteEntry.site;

  intentEnterprise =
    if builtins.hasAttr selectedSiteEntry.enterpriseName fabricInputs
      && builtins.isAttrs fabricInputs.${selectedSiteEntry.enterpriseName}
    then
      fabricInputs.${selectedSiteEntry.enterpriseName}
    else
      { };

  intentSite =
    if builtins.hasAttr selectedSiteEntry.siteName intentEnterprise
      && builtins.isAttrs intentEnterprise.${selectedSiteEntry.siteName}
    then
      intentEnterprise.${selectedSiteEntry.siteName}
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

  policyRuntimeTargetName = runtimeUnitName;

  policyRuntimeTarget = runtimeContext.runtimeTargetForUnit {
    cpm = controlPlaneOut;
    unitName = policyRuntimeTargetName;
    file = "s88/Unit/s-router-policy-only/container/nftables.nix";
  };

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
    else if cpmSite ? attachment && builtins.isList cpmSite.attachment then
      lib.filter (
        attachment:
          builtins.isAttrs attachment
          && attachment ? unit
          && builtins.isString attachment.unit
          && runtimeContext.tenantNameForAttachment attachment != null
      ) cpmSite.attachment
    else
      [ ];

  tenantInterfaceByName =
    builtins.listToAttrs (
      lib.filter (entry: entry != null) (
        map (
          attachment:
          let
            tenantName =
              runtimeContext.tenantNameForAttachment attachment;

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
          if tenantName != null && selectedIfName != null then
            {
              name = tenantName;
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
