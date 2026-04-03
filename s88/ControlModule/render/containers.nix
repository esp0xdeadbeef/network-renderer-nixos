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
  firewall = import ../firewall/default.nix { inherit lib; };

  uniqueStrings = values: lib.unique (lib.filter builtins.isString values);

  defaultDeploymentHostName =
    if hostPlan != null && builtins.isAttrs hostPlan && hostPlan ? deploymentHostName then
      hostPlan.deploymentHostName
    else if hostPlan != null && builtins.isAttrs hostPlan && hostPlan ? hostName then
      hostPlan.hostName
    else
      null;

  uplinks =
    if
      hostPlan != null
      && builtins.isAttrs hostPlan
      && hostPlan ? uplinks
      && builtins.isAttrs hostPlan.uplinks
    then
      hostPlan.uplinks
    else
      { };

  wanUplinkName =
    if
      hostPlan != null
      && builtins.isAttrs hostPlan
      && hostPlan ? wanUplinkName
      && builtins.isString hostPlan.wanUplinkName
    then
      hostPlan.wanUplinkName
    else
      null;

  flatModels =
    if hostPlan != null then
      import ../mapping/container-runtime.nix {
        inherit lib hostPlan;
      }
    else
      null;

  modelsByHost =
    if containerModelsByHost != null then
      containerModelsByHost
    else if containerModels != null then
      containerModels
    else if deploymentContainers != null then
      deploymentContainers
    else if models != null then
      models
    else
      null;

  tenantBridgeOverrideForInterface =
    iface:
    let
      renderedHostBridgeName =
        if iface ? renderedHostBridgeName && builtins.isString iface.renderedHostBridgeName then
          iface.renderedHostBridgeName
        else
          "";
    in
    if
      (iface ? sourceKind && iface.sourceKind == "tenant")
      && (iface ? backingRef && builtins.isAttrs iface.backingRef)
      && (iface.backingRef ? kind && iface.backingRef.kind == "attachment")
      && (
        iface.backingRef ? name && builtins.isString iface.backingRef.name && iface.backingRef.name != ""
      )
      && lib.hasPrefix "rt--tena-" renderedHostBridgeName
    then
      iface.backingRef.name
    else
      null;

  tenantBridgeOverrides =
    model:
    lib.foldl' (
      acc: iface:
      let
        override = tenantBridgeOverrideForInterface iface;

        vethName =
          if iface ? hostVethName && builtins.isString iface.hostVethName && iface.hostVethName != "" then
            iface.hostVethName
          else if
            iface ? containerInterfaceName
            && builtins.isString iface.containerInterfaceName
            && iface.containerInterfaceName != ""
          then
            iface.containerInterfaceName
          else
            null;
      in
      if override != null && vethName != null then acc // { ${vethName} = override; } else acc
    ) { } (builtins.attrValues (model.interfaces or { }));

  applyTenantBridgeOverrides =
    model:
    let
      overrides = tenantBridgeOverrides model;

      renderedVeths = lib.mapAttrs (
        vethName: veth:
        if builtins.hasAttr vethName overrides then
          veth
          // {
            hostBridge = overrides.${vethName};
          }
        else
          veth
      ) (model.veths or { });

      renderedInterfaces = lib.mapAttrs (
        _: iface:
        let
          vethName =
            if iface ? hostVethName && builtins.isString iface.hostVethName && iface.hostVethName != "" then
              iface.hostVethName
            else if
              iface ? containerInterfaceName
              && builtins.isString iface.containerInterfaceName
              && iface.containerInterfaceName != ""
            then
              iface.containerInterfaceName
            else
              null;
        in
        if vethName != null && builtins.hasAttr vethName overrides then
          iface
          // {
            renderedHostBridgeName = overrides.${vethName};
          }
        else
          iface
      ) (model.interfaces or { });
    in
    model
    // {
      veths = renderedVeths;
      interfaces = renderedInterfaces;
    };

  mkFirewallArg =
    nftRuleset:
    if builtins.isString nftRuleset && nftRuleset != "" then
      {
        enable = true;
        ruleset = nftRuleset;
      }
    else
      {
        enable = false;
        ruleset = null;
      };

  firewallArgForModel =
    renderedModel:
    if cpm == null then
      if renderedModel ? firewall && builtins.isAttrs renderedModel.firewall then
        renderedModel.firewall
      else
        {
          enable = false;
          ruleset = null;
        }
    else
      mkFirewallArg (firewall {
        inherit cpm inventory uplinks;
        unitKey = if renderedModel ? unitKey then renderedModel.unitKey else null;
        unitName = if renderedModel ? unitName then renderedModel.unitName else null;
        roleName = if renderedModel ? roleName then renderedModel.roleName else null;
        runtimeTarget =
          if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
            renderedModel.runtimeTarget
          else
            { };
        interfaces =
          if renderedModel ? interfaces && builtins.isAttrs renderedModel.interfaces then
            renderedModel.interfaces
          else
            { };
        wanIfs =
          if renderedModel ? wanInterfaceNames && builtins.isList renderedModel.wanInterfaceNames then
            renderedModel.wanInterfaceNames
          else
            [ ];
        lanIfs =
          if renderedModel ? lanInterfaceNames && builtins.isList renderedModel.lanInterfaceNames then
            renderedModel.lanInterfaceNames
          else
            [ ];
      });

  commonRouterConfig =
    {
      lib,
      pkgs,
      ...
    }:
    {
      boot.isContainer = true;

      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;
      networking.networkmanager.enable = false;
      networking.useHostResolvConf = lib.mkForce false;

      services.resolved.enable = lib.mkForce false;
      networking.firewall.enable = lib.mkForce false;

      environment.systemPackages = with pkgs; [
        gron
        traceroute
        tcpdump
        nftables
        dnsutils
        iproute2
        iputils
      ];

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      system.stateVersion = "25.11";
    };

  containerConfigModuleFor =
    containerName: renderedModel: firewallArg:
    let
      containerNetworks = import ./container-networks.nix {
        inherit
          lib
          uplinks
          wanUplinkName
          ;
        containerModel = renderedModel;
      };

      roleName = renderedModel.roleName or null;

      profilePath = if renderedModel ? profilePath then renderedModel.profilePath else null;

      resolvedHostName =
        if renderedModel ? unitName && builtins.isString renderedModel.unitName then
          renderedModel.unitName
        else
          containerName;
    in
    {
      lib,
      pkgs,
      ...
    }:
    let
      accessServices =
        if roleName == "access" then
          import ../access/render/default.nix {
            inherit lib pkgs;
            containerModel = renderedModel;
          }
        else
          { };
    in
    {
      imports = lib.optionals (profilePath != null) [ profilePath ];

      config = lib.mkMerge [
        (commonRouterConfig { inherit lib pkgs; })

        {
          networking.hostName = resolvedHostName;
          systemd.network.networks = containerNetworks;
        }

        accessServices

        (lib.optionalAttrs firewallArg.enable {
          networking.nftables.enable = true;
          networking.nftables.ruleset = firewallArg.ruleset;
        })
      ];
    };

  mkContainer =
    deploymentHostName: containerName: model:
    let
      renderedModel = applyTenantBridgeOverrides model;

      firewallArg = firewallArgForModel renderedModel;
    in
    {
      autoStart =
        if renderedModel ? autoStart && builtins.isBool renderedModel.autoStart then
          renderedModel.autoStart
        else
          true;

      privateNetwork = true;

      bindMounts =
        if renderedModel ? bindMounts && builtins.isAttrs renderedModel.bindMounts then
          renderedModel.bindMounts
        else
          { };

      extraVeths = renderedModel.veths or { };

      allowedDevices = uniqueStrings (
        if renderedModel ? allowedDevices && builtins.isList renderedModel.allowedDevices then
          renderedModel.allowedDevices
        else
          [ ]
      );

      additionalCapabilities = uniqueStrings (
        [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ]
        ++ (
          if
            renderedModel ? additionalCapabilities && builtins.isList renderedModel.additionalCapabilities
          then
            renderedModel.additionalCapabilities
          else
            [ ]
        )
      );

      config = containerConfigModuleFor containerName renderedModel firewallArg;

      specialArgs = {
        inherit deploymentHostName;
        s88RoleName = renderedModel.roleName or null;
        s88Firewall = firewallArg;
        unitName =
          if renderedModel ? unitName && builtins.isString renderedModel.unitName then
            renderedModel.unitName
          else
            containerName;
      }
      // lib.optionalAttrs debugEnabled {
        s88Debug = renderedModel;
      };
    };

  renderFlatContainers =
    containerModelsFlat:
    builtins.mapAttrs (
      containerName: model:
      mkContainer (
        if model ? deploymentHostName && builtins.isString model.deploymentHostName then
          model.deploymentHostName
        else
          defaultDeploymentHostName
      ) containerName model
    ) containerModelsFlat;

  renderNestedContainers =
    nestedModels:
    lib.mapAttrs (
      deploymentHostName: deploymentHostContainers:
      builtins.mapAttrs (
        containerName: model: mkContainer deploymentHostName containerName model
      ) deploymentHostContainers
    ) nestedModels;
in
if flatModels != null then
  renderFlatContainers flatModels
else if modelsByHost != null then
  renderNestedContainers modelsByHost
else
  { }
