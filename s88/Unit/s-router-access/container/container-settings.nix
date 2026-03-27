{
  config,
  lib,
  outPath,
  controlPlaneOut,
  globalInventory,
  ...
}:

let
  hostname = config.networking.hostName;
  inventory = globalInventory;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  cpmData =
    if controlPlaneOut ? control_plane_model
      && builtins.isAttrs controlPlaneOut.control_plane_model
      && controlPlaneOut.control_plane_model ? data
      && builtins.isAttrs controlPlaneOut.control_plane_model.data
    then
      controlPlaneOut.control_plane_model.data
    else
      throw ''
        container-settings:

        controlPlaneOut.control_plane_model.data missing.

        Top-level keys:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames controlPlaneOut)}
      '';

  siteEntries =
    lib.concatMap (
      enterpriseName:
      let
        enterprise = cpmData.${enterpriseName};
      in
      map (
        siteName:
        {
          inherit enterpriseName siteName;
          site = enterprise.${siteName};
        }
      ) (sortedAttrNames enterprise)
    ) (sortedAttrNames cpmData);

  runtimeTargets =
    lib.foldl' (
      acc: entry:
      acc // (
        if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
          entry.site.runtimeTargets
        else
          { }
      )
    ) { } siteEntries;

  runtimeTargetNames = sortedAttrNames runtimeTargets;

  realizationNodes =
    if inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      throw ''
        container-settings:

        inventory.realization.nodes missing.

        inventory:
        ${builtins.toJSON inventory}
      '';

  logicalNodeNameForUnit =
    unitName:
    let
      target = runtimeTargets.${unitName};
    in
    if target ? logicalNode
      && builtins.isAttrs target.logicalNode
      && target.logicalNode ? name
      && builtins.isString target.logicalNode.name
    then
      target.logicalNode.name
    else
      null;

  placementHostForUnit =
    unitName:
    let
      target = runtimeTargets.${unitName};
    in
    if target ? placement
      && builtins.isAttrs target.placement
      && target.placement ? host
      && builtins.isString target.placement.host
    then
      target.placement.host
    else
      null;

  realizationHostForUnit =
    unitName:
    if builtins.hasAttr unitName realizationNodes
      && builtins.isAttrs realizationNodes.${unitName}
      && realizationNodes.${unitName} ? host
      && builtins.isString realizationNodes.${unitName}.host
    then
      realizationNodes.${unitName}.host
    else
      null;

  unitBelongsToHost =
    unitName:
      logicalNodeNameForUnit unitName == hostname
      || unitName == hostname
      || lib.hasPrefix "${hostname}-" unitName
      || placementHostForUnit unitName == hostname
      || realizationHostForUnit unitName == hostname;

  selectedUnits = lib.filter unitBelongsToHost runtimeTargetNames;

  _selectedNonEmpty =
    if selectedUnits != [ ] then
      true
    else
      throw ''
        container-settings:

        No runtime targets matched host '${hostname}'.

        Available runtime targets:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ runtimeTargetNames)}
      '';

  runtimeTransitBridgeForUnit =
    unitName:
      let
        realizationNode =
          if builtins.hasAttr unitName realizationNodes then
            realizationNodes.${unitName}
          else
            throw ''
              container-settings:

              Missing realization node for unit '${unitName}'.

              Known realization nodes:
              ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames realizationNodes)}
            '';

        ports =
          if realizationNode ? ports && builtins.isAttrs realizationNode.ports then
            realizationNode.ports
          else
            throw ''
              container-settings:

              realization.nodes.${unitName}.ports missing or not an attrset.

              realization node:
              ${builtins.toJSON realizationNode}
            '';

        portValues = map (name: ports.${name}) (builtins.attrNames ports);

        bridgePorts =
          builtins.filter (
            port:
              builtins.isAttrs port
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "bridge"
              && port.attach ? bridge
              && builtins.isString port.attach.bridge
          ) portValues;
      in
      if builtins.length bridgePorts == 1 then
        (builtins.head bridgePorts).attach.bridge
      else
        throw ''
          container-settings:

          Expected exactly 1 bridge-backed runtime port for unit '${unitName}'.

          bridge-backed ports:
          ${builtins.toJSON bridgePorts}
        '';

  tenantNameForUnit =
    unitName:
    let
      logicalName =
        let
          fromTarget = logicalNodeNameForUnit unitName;
        in
        if fromTarget != null then
          fromTarget
        else if builtins.hasAttr unitName realizationNodes
          && realizationNodes.${unitName} ? logicalNode
          && builtins.isAttrs realizationNodes.${unitName}.logicalNode
          && realizationNodes.${unitName}.logicalNode ? name
          && builtins.isString realizationNodes.${unitName}.logicalNode.name
        then
          realizationNodes.${unitName}.logicalNode.name
        else
          unitName;
    in
    if lib.hasPrefix "s-router-access-" logicalName then
      builtins.substring
        (builtins.stringLength "s-router-access-")
        (builtins.stringLength logicalName - builtins.stringLength "s-router-access-")
        logicalName
    else
      throw ''
        container-settings:

        Cannot derive tenant name from logical node '${logicalName}' for unit '${unitName}'.
      '';

  siteEntryForUnit =
    unitName:
    let
      tenantName = tenantNameForUnit unitName;

      matches =
        builtins.filter (
          entry:
          entry.site ? attachments
          && builtins.isList entry.site.attachments
          && builtins.any (
            attachment:
            builtins.isAttrs attachment
            && (attachment.kind or null) == "tenant"
            && (attachment.name or null) == tenantName
            && (attachment.unit or null) == unitName
          ) entry.site.attachments
        ) siteEntries;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        container-settings:

        Could not uniquely resolve site for unit '${unitName}'.

        tenantName: ${tenantName}
      '';

  tenantDomainForUnit =
    unitName:
    let
      tenantName = tenantNameForUnit unitName;
      site = (siteEntryForUnit unitName).site;

      domains =
        if site ? domains
          && builtins.isAttrs site.domains
          && site.domains ? tenants
          && builtins.isList site.domains.tenants
        then
          site.domains.tenants
        else
          [ ];

      matches =
        builtins.filter (
          domain:
          builtins.isAttrs domain
          && (domain.name or null) == tenantName
          && domain ? ipv4
          && builtins.isString domain.ipv4
          && domain ? ipv6
          && builtins.isString domain.ipv6
        ) domains;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        container-settings:

        Could not uniquely resolve tenant domain for unit '${unitName}'.

        tenantName: ${tenantName}
      '';

  tenantVlanForUnit =
    unitName:
      let
        cidr = (tenantDomainForUnit unitName).ipv4;
        addr = builtins.elemAt (lib.splitString "/" cidr) 0;
        octets = lib.splitString "." addr;
      in
      if builtins.length octets == 4 then
        builtins.fromJSON (builtins.elemAt octets 2)
      else
        throw ''
          container-settings:

          Cannot derive tenant VLAN from IPv4 CIDR '${cidr}' for unit '${unitName}'.
        '';

  mkContainer =
    unitName:
    let
      transitBridge = runtimeTransitBridgeForUnit unitName;
      tenantVlan = tenantVlanForUnit unitName;
      tenantDomain = tenantDomainForUnit unitName;
    in
    {
      name = unitName;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "lan-${toString tenantVlan}" = {
            hostBridge = "br-lan-${toString tenantVlan}";
          };
          "tr-${toString tenantVlan}" = {
            hostBridge = transitBridge;
          };
        };

        specialArgs = {
          inherit outPath;
          fabricNodeContext = runtimeTargets.${unitName};
          tenantNetwork = {
            name = tenantNameForUnit unitName;
            ipv4 = tenantDomain.ipv4;
            ipv6 = tenantDomain.ipv6;
          };
          vlanId = tenantVlan;
          transitVlanId = tenantVlan;
          policyAccessTransitBase = 100;
        };

        config = { ... }: {
          imports = [
            ./node-from-topology.nix
            ./networkd-from-topology.nix
            ./kea.nix
            ./kea-services.nix
            ./dns.nix
            ./radvd.nix
            ../debugging-packages.nix
          ];

          boot.isContainer = true;
          system.stateVersion = "25.11";

          networking.hostName = unitName;
          networking.useHostResolvConf = false;

          networking.firewall.enable = false;
          services.resolved.enable = false;
        };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_SYS_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];
      };
    };
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  containers = builtins.listToAttrs (map mkContainer selectedUnits);
}
