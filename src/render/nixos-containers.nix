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

  normalizeOptionalBool =
    label: value:
    if value == null then
      null
    else if builtins.isBool value then
      value
    else
      throw "network-renderer-nixos: expected ${label} to be a boolean";

  ensureAttrs =
    label: value:
    if builtins.isAttrs value then
      value
    else
      throwWithValue "network-renderer-nixos: expected ${label} to be an attribute set" value;

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

  normalizeParsedRouteEntry =
    label: familyHint: value:
    let
      route =
        if builtins.isAttrs value then
          value
        else
          throwWithValue "network-renderer-nixos: expected ${label} to be an attribute set" {
            inherit label value;
          };

      destination = normalizeOptionalString "${label}.dst" (
        if route ? dst then
          route.dst
        else if route ? destination then
          route.destination
        else if route ? to then
          route.to
        else if route ? prefix then
          route.prefix
        else if route ? cidr then
          route.cidr
        else if route ? network then
          route.network
        else
          null
      );

      gateway = normalizeOptionalString "${label}.via" (
        if route ? via4 then
          route.via4
        else if route ? via6 then
          route.via6
        else if route ? gateway then
          route.gateway
        else if route ? via then
          route.via
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

      family =
        if familyHint != null then
          familyHint
        else if route ? family && builtins.isString route.family && route.family != "" then
          route.family
        else
          inferRouteFamily destination gateway;

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

      normalizedDestination =
        if destination == "0.0.0.0/0" || destination == "::/0" then "default" else destination;

      _validateFamily =
        if family == "ipv4" || family == "ipv6" then
          true
        else
          throwWithValue "network-renderer-nixos: unsupported ${label}.family '${family}'" {
            inherit
              label
              route
              family
              ;
          };

      _validateRoute =
        if normalizedDestination != null then
          true
        else
          throwWithValue
            "network-renderer-nixos: parsed route '${label}' is missing dst/destination/to/prefix/cidr/network"
            {
              inherit label route;
            };
    in
    builtins.seq _validateFamily (
      builtins.seq _validateRoute {
        inherit
          family
          gateway
          metric
          onLink
          ;
        destination = normalizedDestination;
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

  parseRuntimeTargetRoutes =
    rawRoutes:
    let
      routeFamilies =
        if builtins.isAttrs rawRoutes then
          rawRoutes
        else
          throwWithValue "network-renderer-nixos: expected interface.routes to be an attribute set with ipv4/ipv6 lists" rawRoutes;

      parseFamily =
        familyName:
        let
          familyValue =
            if builtins.hasAttr familyName routeFamilies then routeFamilies.${familyName} else [ ];
        in
        if familyValue == null then
          [ ]
        else if builtins.isList familyValue then
          map (entry: normalizeParsedRouteEntry "interface.routes.${familyName}" familyName entry) familyValue
        else
          throwWithValue "network-renderer-nixos: expected interface.routes.${familyName} to be a list" familyValue;
    in
    parseFamily "ipv4" ++ parseFamily "ipv6";

  normalizeInterfaceIpConfig =
    label: value:
    if value == null then
      { }
    else
      let
        cfg = ensureAttrs label value;
      in
      {
        enable = normalizeOptionalBool "${label}.enable" (cfg.enable or null);
        dhcp = normalizeOptionalBool "${label}.dhcp" (cfg.dhcp or null);
        acceptRA = normalizeOptionalBool "${label}.acceptRA" (cfg.acceptRA or null);
        dhcpv6PD = normalizeOptionalBool "${label}.dhcpv6PD" (cfg.dhcpv6PD or null);
        method = normalizeOptionalString "${label}.method" (cfg.method or null);
      };

  interfaceUsesDhcp4 = ip4: (ip4.dhcp or false) || (ip4.method or null) == "dhcp";

  interfaceUsesDhcp6 = ip6: (ip6.dhcp or false) || (ip6.method or null) == "dhcp";

  interfaceUsesAcceptRA = ip6: (ip6.acceptRA or false) || (ip6.method or null) == "slaac";

  networkdDhcpValue =
    ip4: ip6:
    let
      use4 = interfaceUsesDhcp4 ip4;
      use6 = interfaceUsesDhcp6 ip6;
    in
    if use4 && use6 then
      "yes"
    else if use4 then
      "ipv4"
    else if use6 then
      "ipv6"
    else
      null;

  routesForInterface =
    rawInterface:
    let
      parsedRuntimeTargetRoutes =
        if rawInterface ? routes && rawInterface.routes != null then
          parseRuntimeTargetRoutes rawInterface.routes
        else
          [ ];

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
    dedupeRoutes (parsedRuntimeTargetRoutes ++ defaultGatewayRoutes);

  normalizeArtifactEntry =
    containerName: artifactPath: artifact:
    let
      entry =
        if builtins.isAttrs artifact then
          artifact
        else
          throwWithValue "network-renderer-nixos: expected artifactFiles.${artifactPath} for container '${containerName}' to be an attribute set" artifact;

      format =
        if entry ? format && builtins.isString entry.format && entry.format != "" then
          entry.format
        else
          throwWithValue "network-renderer-nixos: artifactFiles.${artifactPath} for container '${containerName}' is missing format" entry;

      value =
        if entry ? value then
          entry.value
        else
          throwWithValue "network-renderer-nixos: artifactFiles.${artifactPath} for container '${containerName}' is missing value" entry;

      etcPath =
        if builtins.isString artifactPath && artifactPath != "" then
          "network-artifacts/${artifactPath}"
        else
          throw "network-renderer-nixos: artifact path for container '${containerName}' must be a non-empty string";
    in
    {
      name = etcPath;
      value =
        if format == "json" then
          {
            text = builtins.toJSON value;
          }
        else if format == "text" then
          {
            text =
              if builtins.isString value then
                value
              else
                throwWithValue "network-renderer-nixos: text artifactFiles.${artifactPath} for container '${containerName}' must have a string value" value;
          }
        else
          throw "network-renderer-nixos: unsupported artifact format '${format}' for container '${containerName}'";
    };

  artifactEtcForContainer =
    containerName: container:
    let
      artifactFiles =
        if container ? artifactFiles && builtins.isAttrs container.artifactFiles then
          container.artifactFiles
        else
          { };
    in
    builtins.listToAttrs (
      map (
        artifactPath: normalizeArtifactEntry containerName artifactPath artifactFiles.${artifactPath}
      ) (sortedAttrNames artifactFiles)
    );

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

          ip4 = normalizeInterfaceIpConfig "interface.ipv4" (rawInterface.ipv4 or null);
          ip6 = normalizeInterfaceIpConfig "interface.ipv6" (rawInterface.ipv6 or null);

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
          dhcp = networkdDhcpValue ip4 ip6;
          ipv6AcceptRA = interfaceUsesAcceptRA ip6;
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

      renameServiceScript = lib.concatStringsSep "\n" (
        map (entry: ''
          if ip link show dev "${entry.hostVethName}" >/dev/null 2>&1; then
            ip link set dev "${entry.hostVethName}" down || true
            ip link set dev "${entry.hostVethName}" name "${entry.containerInterfaceName}"
          fi
          ip link set dev "${entry.containerInterfaceName}" up
        '') renderedInterfaceEntries
      );

      renderedInterfaceNetworks = builtins.listToAttrs (
        map (
          entry:
          let
            routeEntries = map (
              route:
              {
                Destination = route.destination;
              }
              // lib.optionalAttrs (route.gateway != null) {
                Gateway = route.gateway;
              }
              // lib.optionalAttrs (route.metric != null) {
                Metric = route.metric;
              }
              // lib.optionalAttrs route.onLink {
                GatewayOnLink = true;
              }
            ) entry.routes;
          in
          {
            name = "10-${entry.containerInterfaceName}";
            value = {
              matchConfig.Name = entry.containerInterfaceName;
              address = lib.filter (value: value != null) [
                entry.address4
                entry.address6
              ];
              routes = routeEntries;
              networkConfig =
                (lib.optionalAttrs (entry.dhcp != null) {
                  DHCP = entry.dhcp;
                })
                // (lib.optionalAttrs entry.ipv6AcceptRA {
                  IPv6AcceptRA = true;
                });
            };
          }
        ) renderedInterfaceEntries
      );

      forwardingServiceScript = ''
        echo 1 > /proc/sys/net/ipv4/ip_forward
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
        echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
        echo 0 > /proc/sys/net/ipv4/conf/default/rp_filter
      '';

      artifactEtc = artifactEtcForContainer containerName container;

      nftablesArtifactPath =
        if
          container ? nftablesArtifactPath
          && builtins.isString container.nftablesArtifactPath
          && container.nftablesArtifactPath != ""
        then
          container.nftablesArtifactPath
        else
          null;

      nftablesRuleset =
        if nftablesArtifactPath == null then
          null
        else
          let
            artifactKey = "network-artifacts/${nftablesArtifactPath}";
          in
          if builtins.hasAttr artifactKey artifactEtc then
            artifactEtc.${artifactKey}.text
          else
            throw "network-renderer-nixos: missing nftables artifact '${artifactKey}' for container '${containerName}'";

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
        "bindMounts"
        "artifactFiles"
        "nftablesArtifactPath"
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
              networking.firewall.enable = false;
              services.resolved.enable = false;

              systemd.network.enable = true;
              systemd.network.networks = renderedInterfaceNetworks;

              networking.nftables.enable = lib.mkIf (nftablesRuleset != null) true;
              networking.nftables.ruleset = lib.mkIf (nftablesRuleset != null) nftablesRuleset;

              environment.etc = artifactEtc;

              environment.systemPackages = with pkgs; [
                bind
                dig
                dnsutils
                gron
                iproute2
                iputils
                jq
                mtr
                nftables
                procps
                tcpdump
                traceroute
              ];

              systemd.services.enable-container-forwarding = {
                wantedBy = [ "network-pre.target" ];
                before = [
                  "network-pre.target"
                  "systemd-networkd.service"
                  "nftables.service"
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                path = [ pkgs.procps ];
                script = forwardingServiceScript;
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
                  "25.11";
            };
        }
      )
    )
  ) containerModel.containers
)
