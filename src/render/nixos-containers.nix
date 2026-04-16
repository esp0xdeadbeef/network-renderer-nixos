{ lib }:
containerModel:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  safeJson =
    value:
    let
      render =
        depth: current:
        let
          currentType = builtins.typeOf current;
        in
        if depth >= 6 then
          if currentType == "set" then
            {
              __type = "set";
              __keys = sortedAttrNames current;
            }
          else if currentType == "list" then
            {
              __type = "list";
              __length = builtins.length current;
            }
          else if currentType == "path" then
            toString current
          else if currentType == "lambda" then
            "<lambda>"
          else
            current
        else if currentType == "set" then
          builtins.listToAttrs (
            map (name: {
              inherit name;
              value = render (depth + 1) current.${name};
            }) (sortedAttrNames current)
          )
        else if currentType == "list" then
          map (entry: render (depth + 1) entry) current
        else if currentType == "path" then
          toString current
        else if currentType == "lambda" then
          "<lambda>"
        else
          current;
    in
    builtins.toJSON (render 0 value);

  throwWithValue =
    message: value:
    throw ''
      ${message}
      value=${safeJson value}
    '';

  ensureUniqueNames =
    label: names:
    if builtins.length names == builtins.length (lib.unique names) then
      true
    else
      throw "network-renderer-nixos: duplicate ${label}: ${builtins.toJSON names}";

  mergeAttrsUnique =
    label: left: right:
    let
      duplicates = lib.filter (name: builtins.hasAttr name right) (sortedAttrNames left);
    in
    if duplicates == [ ] then
      left // right
    else
      throw "network-renderer-nixos: duplicate ${label}: ${builtins.toJSON duplicates}";

  hashFragment = value: builtins.substring 0 11 (builtins.hashString "sha256" value);

  normalizeOptionalAddress =
    value:
    if value == null then
      null
    else if builtins.isString value && value != "" then
      value
    else
      null;

  normalizeOptionalString =
    label: value:
    if value == null then
      null
    else if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${label} to be a non-empty string";

  normalizeOptionalInt =
    label: value:
    if value == null then
      null
    else if builtins.isInt value then
      value
    else
      throw "network-renderer-nixos: expected ${label} to be an integer";

  inferRouteFamily =
    destination: gateway:
    if gateway != null && lib.hasInfix ":" gateway then
      "ipv6"
    else if destination != null && destination != "default" && lib.hasInfix ":" destination then
      "ipv6"
    else
      "ipv4";

  normalizeDefaultGatewayRoute =
    label: value:
    let
      gateway = normalizeOptionalString "${label}.gateway" value;
      family = inferRouteFamily "default" gateway;
    in
    {
      inherit family gateway;
      destination = "default";
      metric = null;
      onLink = false;
    };

  hasRouteFields =
    route:
    builtins.any (name: builtins.hasAttr name route) [
      "destination"
      "to"
      "prefix"
      "cidr"
      "dst"
      "network"
      "gateway"
      "via"
      "via4"
      "via6"
      "nextHop"
      "next_hop"
      "gw"
      "router"
    ];

  isFamilyRouteMap =
    value:
    builtins.isAttrs value
    && value != { }
    && lib.all (name: name == "ipv4" || name == "ipv6") (sortedAttrNames value);

  normalizeShorthandRouteAttrset =
    label: route:
    let
      names = sortedAttrNames route;
    in
    if hasRouteFields route || isFamilyRouteMap route then
      route
    else if builtins.length names == 1 then
      let
        onlyName = builtins.head names;
        onlyValue = route.${onlyName};
      in
      if onlyName == "default" then
        if builtins.isString onlyValue && onlyValue != "" then
          {
            destination = "default";
            gateway = onlyValue;
          }
        else if builtins.isAttrs onlyValue then
          { destination = "default"; } // onlyValue
        else
          route
      else if
        onlyName == "gateway"
        || onlyName == "via"
        || onlyName == "via4"
        || onlyName == "via6"
        || onlyName == "nextHop"
        || onlyName == "next_hop"
        || onlyName == "gw"
        || onlyName == "router"
      then
        if builtins.isString onlyValue && onlyValue != "" then
          {
            destination = "default";
            "${onlyName}" = onlyValue;
          }
        else
          route
      else if builtins.isString onlyValue && onlyValue != "" then
        {
          destination = onlyName;
          gateway = onlyValue;
        }
      else if builtins.isAttrs onlyValue then
        {
          destination = onlyName;
        }
        // onlyValue
      else
        route
    else
      let
        mappedEntries = lib.concatMap (
          name:
          let
            item = route.${name};
          in
          if item == null then
            [ ]
          else if builtins.isString item && item != "" then
            [
              {
                destination = name;
                gateway = item;
              }
            ]
          else if builtins.isAttrs item then
            [
              (
                {
                  destination = name;
                }
                // item
              )
            ]
          else
            throwWithValue
              "network-renderer-nixos: expected route map entry '${label}.${name}' to be a non-empty string or attribute set"
              {
                label = "${label}.${name}";
                item = item;
                route = route;
              }
        ) names;
      in
      if mappedEntries == [ ] then route else mappedEntries;

  normalizeRouteEntry =
    label: value:
    let
      route =
        if builtins.isAttrs value then
          let
            normalized = normalizeShorthandRouteAttrset label value;
          in
          if builtins.isList normalized then
            throwWithValue
              "network-renderer-nixos: internal error: normalizeRouteEntry received multi-entry route map"
              {
                inherit label value normalized;
              }
          else
            normalized
        else if builtins.isString value && value != "" then
          { destination = value; }
        else
          throwWithValue
            "network-renderer-nixos: expected ${label} to be an attribute set or non-empty string"
            {
              inherit label value;
            };

      destination = normalizeOptionalString "${label}.destination" (
        if route ? destination then
          route.destination
        else if route ? to then
          route.to
        else if route ? prefix then
          route.prefix
        else if route ? cidr then
          route.cidr
        else if route ? dst then
          route.dst
        else if route ? network then
          route.network
        else
          null
      );

      gateway = normalizeOptionalString "${label}.gateway" (
        if route ? gateway then
          route.gateway
        else if route ? via then
          route.via
        else if route ? via4 then
          route.via4
        else if route ? via6 then
          route.via6
        else if route ? nextHop then
          route.nextHop
        else if route ? next_hop then
          route.next_hop
        else if route ? gw then
          route.gw
        else if route ? router then
          route.router
        else
          null
      );

      family = normalizeOptionalString "${label}.family" (route.family or null);

      metric = normalizeOptionalInt "${label}.metric" (route.metric or null);

      onLink =
        if route ? onLink then
          if builtins.isBool route.onLink then
            route.onLink
          else
            throwWithValue "network-renderer-nixos: expected ${label}.onLink to be a boolean" {
              inherit label route;
              onLink = route.onLink;
            }
        else
          false;

      resolvedFamily = if family != null then family else inferRouteFamily destination gateway;

      _validateFamily =
        if resolvedFamily == "ipv4" || resolvedFamily == "ipv6" then
          true
        else
          throwWithValue "network-renderer-nixos: unsupported ${label}.family '${resolvedFamily}'" {
            inherit
              label
              route
              destination
              gateway
              family
              resolvedFamily
              ;
          };

      _validateRoute =
        if destination != null || gateway != null then
          true
        else
          throwWithValue
            "network-renderer-nixos: route '${label}' requires destination/to/prefix/cidr/dst/network or gateway/via/via4/via6/nextHop/next_hop/gw/router"
            {
              inherit label route;
            };
    in
    builtins.seq _validateFamily (
      builtins.seq _validateRoute {
        family = resolvedFamily;
        inherit
          destination
          gateway
          metric
          onLink
          ;
      }
    );

  routeKey =
    route:
    builtins.toJSON {
      inherit (route)
        family
        destination
        gateway
        metric
        onLink
        ;
    };

  dedupeRoutes =
    routes:
    let
      folded =
        builtins.foldl'
          (
            acc: route:
            let
              key = routeKey route;
            in
            if builtins.hasAttr key acc.byKey then
              acc
            else
              {
                order = acc.order ++ [ key ];
                byKey = acc.byKey // {
                  "${key}" = route;
                };
              }
          )
          {
            order = [ ];
            byKey = { };
          }
          routes;
    in
    map (key: folded.byKey.${key}) folded.order;

  normalizeRouteEntriesValue =
    label: value:
    if value == null then
      [ ]
    else if builtins.isList value then
      lib.concatMap (
        entry:
        if builtins.isAttrs entry then
          let
            normalized = normalizeShorthandRouteAttrset "${label} entry" entry;
          in
          if builtins.isList normalized then
            map (route: normalizeRouteEntry "${label} entry" route) normalized
          else
            [ (normalizeRouteEntry "${label} entry" normalized) ]
        else
          [ (normalizeRouteEntry "${label} entry" entry) ]
      ) value
    else if builtins.isAttrs value then
      let
        names = sortedAttrNames value;
      in
      if isFamilyRouteMap value then
        lib.concatMap (
          familyName:
          let
            familyValue = value.${familyName};
            normalizedFamilyEntries =
              if familyValue == null then
                [ ]
              else if builtins.isList familyValue then
                lib.concatMap (
                  entry:
                  if builtins.isAttrs entry then
                    let
                      normalized = normalizeShorthandRouteAttrset "${label}.${familyName} entry" entry;
                    in
                    if builtins.isList normalized then
                      map (
                        route:
                        let
                          normalizedRoute = normalizeRouteEntry "${label}.${familyName} entry" route;
                        in
                        if normalizedRoute.family == familyName then
                          normalizedRoute
                        else
                          normalizedRoute // { family = familyName; }
                      ) normalized
                    else
                      let
                        normalizedRoute = normalizeRouteEntry "${label}.${familyName} entry" normalized;
                      in
                      [
                        (
                          if normalizedRoute.family == familyName then
                            normalizedRoute
                          else
                            normalizedRoute // { family = familyName; }
                        )
                      ]
                  else
                    let
                      normalizedRoute = normalizeRouteEntry "${label}.${familyName} entry" entry;
                    in
                    [
                      (
                        if normalizedRoute.family == familyName then
                          normalizedRoute
                        else
                          normalizedRoute // { family = familyName; }
                      )
                    ]
                ) familyValue
              else if builtins.isAttrs familyValue then
                let
                  normalized = normalizeShorthandRouteAttrset "${label}.${familyName}" familyValue;
                in
                if builtins.isList normalized then
                  map (
                    route:
                    let
                      normalizedRoute = normalizeRouteEntry "${label}.${familyName}" route;
                    in
                    if normalizedRoute.family == familyName then
                      normalizedRoute
                    else
                      normalizedRoute // { family = familyName; }
                  ) normalized
                else
                  let
                    normalizedRoute = normalizeRouteEntry "${label}.${familyName}" normalized;
                  in
                  [
                    (
                      if normalizedRoute.family == familyName then
                        normalizedRoute
                      else
                        normalizedRoute // { family = familyName; }
                    )
                  ]
              else if builtins.isString familyValue && familyValue != "" then
                let
                  normalizedRoute = normalizeRouteEntry "${label}.${familyName}" familyValue;
                in
                [
                  (
                    if normalizedRoute.family == familyName then
                      normalizedRoute
                    else
                      normalizedRoute // { family = familyName; }
                  )
                ]
              else
                throwWithValue
                  "network-renderer-nixos: expected ${label}.${familyName} to be a list, attribute set, or non-empty string"
                  {
                    inherit
                      label
                      familyName
                      familyValue
                      value
                      ;
                  };
          in
          normalizedFamilyEntries
        ) names
      else
        let
          normalizedDirect = normalizeShorthandRouteAttrset label value;
        in
        if builtins.isList normalizedDirect then
          map (route: normalizeRouteEntry label route) normalizedDirect
        else
          [ (normalizeRouteEntry label normalizedDirect) ]
    else if builtins.isString value && value != "" then
      [ (normalizeRouteEntry label value) ]
    else
      throwWithValue
        "network-renderer-nixos: expected ${label} to be a list, attribute set, or non-empty string"
        {
          inherit label value;
        };

  routesForInterface =
    rawInterface:
    let
      explicitRouteLists =
        lib.concatMap
          (
            attrName:
            if !(builtins.hasAttr attrName rawInterface) || rawInterface.${attrName} == null then
              [ ]
            else
              normalizeRouteEntriesValue "interface.${attrName}" rawInterface.${attrName}
          )
          [
            "routes"
            "routeEntries"
            "staticRoutes"
          ];

      defaultGatewayRoutes =
        lib.concatMap
          (
            attrName:
            if !(builtins.hasAttr attrName rawInterface) || rawInterface.${attrName} == null then
              [ ]
            else
              [ (normalizeDefaultGatewayRoute "interface.${attrName}" rawInterface.${attrName}) ]
          )
          [
            "defaultGateway"
            "defaultGateway4"
            "defaultGateway6"
            "gateway4"
            "gateway6"
          ];
    in
    dedupeRoutes (explicitRouteLists ++ defaultGatewayRoutes);

  hostVethNameFor =
    {
      deploymentHostName,
      containerName,
      nodeName,
      containerInterfaceName,
    }:
    "vh-${hashFragment "${deploymentHostName}:${containerName}:${nodeName}:${containerInterfaceName}"}";

  allContainerNames = sortedAttrNames containerModel.containers;

  allRenderedHostVethNames = lib.concatMap (
    containerName:
    let
      container = containerModel.containers.${containerName};

      interfaceNames =
        if container ? interfaces && builtins.isAttrs container.interfaces then
          sortedAttrNames container.interfaces
        else
          [ ];

      bridgeInterfaceNames = lib.filter (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
        in
        interface.hostBridge != null
      ) interfaceNames;
    in
    map (
      interfaceName:
      let
        interface = container.interfaces.${interfaceName};
      in
      hostVethNameFor {
        deploymentHostName =
          if container ? deploymentHostName && builtins.isString container.deploymentHostName then
            container.deploymentHostName
          else
            containerModel.renderHostName or "host";
        inherit containerName;
        nodeName =
          if container ? nodeName && builtins.isString container.nodeName then
            container.nodeName
          else
            containerName;
        containerInterfaceName = interface.containerInterfaceName;
      }
    ) bridgeInterfaceNames
  ) allContainerNames;

  _uniqueRenderedHostVethNames = ensureUniqueNames "rendered container host veth names" allRenderedHostVethNames;
in
builtins.seq _uniqueRenderedHostVethNames (
  builtins.mapAttrs (
    containerName: container:
    let
      interfaceNames =
        if container ? interfaces && builtins.isAttrs container.interfaces then
          sortedAttrNames container.interfaces
        else
          [ ];

      bridgeInterfaceNames = lib.filter (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
        in
        interface.hostBridge != null
      ) interfaceNames;

      renderedInterfaceEntries = map (
        interfaceName:
        let
          interface = container.interfaces.${interfaceName};
          rawInterface =
            if interface ? interface && builtins.isAttrs interface.interface then interface.interface else { };
          hostVethName = hostVethNameFor {
            deploymentHostName =
              if container ? deploymentHostName && builtins.isString container.deploymentHostName then
                container.deploymentHostName
              else
                containerModel.renderHostName or "host";
            inherit containerName;
            nodeName =
              if container ? nodeName && builtins.isString container.nodeName then
                container.nodeName
              else
                containerName;
            containerInterfaceName = interface.containerInterfaceName;
          };
        in
        {
          hostVethName = hostVethName;
          containerInterfaceName = interface.containerInterfaceName;
          hostBridge = interface.hostBridge;
          address4 = normalizeOptionalAddress (rawInterface.addr4 or null);
          address6 = normalizeOptionalAddress (rawInterface.addr6 or null);
          routes = routesForInterface rawInterface;
          rawInterface = rawInterface;
        }
      ) bridgeInterfaceNames;

      _uniqueContainerHostVethNames = ensureUniqueNames "container '${containerName}' host veth names" (
        map (entry: entry.hostVethName) renderedInterfaceEntries
      );

      _uniqueContainerInterfaceNames = ensureUniqueNames "container '${containerName}' interface names" (
        map (entry: entry.containerInterfaceName) renderedInterfaceEntries
      );

      renderedExtraVeths = builtins.listToAttrs (
        map (entry: {
          name = entry.hostVethName;
          value = {
            hostBridge = entry.hostBridge;
          };
        }) renderedInterfaceEntries
      );

      passthroughExtraVeths =
        if container ? extraVeths && builtins.isAttrs container.extraVeths then
          container.extraVeths
        else
          { };

      mergedExtraVeths =
        mergeAttrsUnique "container '${containerName}' extraVeths" passthroughExtraVeths
          renderedExtraVeths;

      containerTemplateImports =
        if container ? containerTemplate && container.containerTemplate != null then
          if builtins.isList container.containerTemplate then
            container.containerTemplate
          else
            [ container.containerTemplate ]
        else
          [ ];

      containerConfigImports =
        if container ? config && container.config != null then
          if builtins.isList container.config then container.config else [ container.config ]
        else
          [ ];

      containerImports = containerTemplateImports ++ containerConfigImports;

      renderRouteCommand =
        entry: route:
        let
          ipCmd = if route.family == "ipv6" then "ip -6" else "ip";
          destination = if route.destination == null then "default" else route.destination;
          viaClause = lib.optionalString (route.gateway != null) " via ${route.gateway}";
          devClause = " dev \"${entry.containerInterfaceName}\"";
          metricClause = lib.optionalString (route.metric != null) " metric ${toString route.metric}";
          onLinkClause = lib.optionalString route.onLink " onlink";
        in
        "${ipCmd} route replace ${destination}${viaClause}${devClause}${metricClause}${onLinkClause}";

      renameServiceScript = lib.concatStringsSep "\n" (
        map (
          entry:
          ''
            if ip link show dev "${entry.hostVethName}" >/dev/null 2>&1; then
              ip link set dev "${entry.hostVethName}" down || true
              ip link set dev "${entry.hostVethName}" name "${entry.containerInterfaceName}"
            fi
            ip link set dev "${entry.containerInterfaceName}" up
          ''
          + lib.optionalString (entry.address4 != null) ''
            ip addr replace ${entry.address4} dev "${entry.containerInterfaceName}"
          ''
          + lib.optionalString (entry.address6 != null) ''
            ip -6 addr replace ${entry.address6} dev "${entry.containerInterfaceName}"
          ''
          + lib.optionalString (entry.routes != [ ]) ''
            ${lib.concatStringsSep "\n" (map (route: renderRouteCommand entry route) entry.routes)}
          ''
        ) renderedInterfaceEntries
      );

      containerDebug = builtins.toJSON {
        renderHostName = containerModel.renderHostName or null;
        containerName = containerName;
        deploymentHostName = container.deploymentHostName or null;
        nodeName = container.nodeName or null;
        logicalName = container.logicalName or null;
        runtimeRole = container.runtimeRole or null;
        interfaceNames = interfaceNames;
        artifactPaths =
          if container ? artifactEtc && builtins.isAttrs container.artifactEtc then
            sortedAttrNames container.artifactEtc
          else
            [ ];
        interfaces = builtins.listToAttrs (
          map (
            interfaceName:
            let
              interface = container.interfaces.${interfaceName};
              rawInterface =
                if interface ? interface && builtins.isAttrs interface.interface then interface.interface else { };
            in
            {
              name = interfaceName;
              value = {
                hostBridge = interface.hostBridge or null;
                containerInterfaceName = interface.containerInterfaceName or null;
                rawInterface = rawInterface;
                routes = routesForInterface rawInterface;
              };
            }
          ) interfaceNames
        );
      };

      artifactEtc =
        if container ? artifactEtc && builtins.isAttrs container.artifactEtc then
          container.artifactEtc
        else
          { };

      passthrough = builtins.removeAttrs container [
        "containerName"
        "nodeName"
        "logicalName"
        "deploymentHostName"
        "interfaces"
        "containerTemplate"
        "systemStateVersion"
        "config"
        "extraVeths"
        "runtimeRole"
        "artifactEtc"
      ];
    in
    builtins.seq _uniqueContainerHostVethNames (
      builtins.seq _uniqueContainerInterfaceNames (
        passthrough
        // {
          autoStart =
            if container ? autoStart && builtins.isBool container.autoStart then container.autoStart else false;

          privateNetwork =
            if container ? privateNetwork && builtins.isBool container.privateNetwork then
              container.privateNetwork
            else
              true;

          extraVeths = mergedExtraVeths;

          config =
            { pkgs, ... }:
            {
              imports = containerImports;

              networking.hostName =
                if container ? logicalName && builtins.isString container.logicalName then
                  container.logicalName
                else
                  containerName;

              networking.useNetworkd = true;
              networking.useHostResolvConf = false;
              networking.useDHCP = false;
              networking.firewall.enable = false;
              services.resolved.enable = false;

              systemd.network.enable = true;

              boot.kernel.sysctl = {
                "net.ipv4.ip_forward" = 1;
                "net.ipv6.conf.all.forwarding" = 1;
                "net.ipv4.conf.all.rp_filter" = 0;
                "net.ipv4.conf.default.rp_filter" = 0;
              };

              environment.systemPackages = with pkgs; [
                bind
                dig
                dnsutils
                iproute2
                iputils
                jq
                mtr
                nftables
                tcpdump
                traceroute
              ];

              environment.etc = artifactEtc // {
                "network-renderer/network-renderer-nixos.json".text = containerDebug;
              };

              systemd.services.rename-container-interfaces = lib.mkIf (renderedInterfaceEntries != [ ]) {
                wantedBy = [ "network-pre.target" ];
                before = [
                  "network-pre.target"
                  "systemd-networkd.service"
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                path = [ pkgs.iproute2 ];
                script = renameServiceScript;
              };

              system.stateVersion =
                if container ? systemStateVersion && builtins.isString container.systemStateVersion then
                  container.systemStateVersion
                else
                  "24.11";
            };
        }
      )
    )
  ) containerModel.containers
)
