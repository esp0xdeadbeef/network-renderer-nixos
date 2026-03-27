{
  config,
  pkgs,
  lib,
  outPath,
  controlPlaneOut,
  globalInventory,
  ...
}:

let
  hostname = config.networking.hostName;
  renderHosts =
    if globalInventory ? render
      && builtins.isAttrs globalInventory.render
      && globalInventory.render ? hosts
      && builtins.isAttrs globalInventory.render.hosts
    then
      globalInventory.render.hosts
    else
      { };

  renderHostConfig =
    if builtins.hasAttr hostname renderHosts && builtins.isAttrs renderHosts.${hostname} then
      renderHosts.${hostname}
    else
      { };

  hostName = hostname;

  containerName =
    if renderHostConfig ? containerName && builtins.isString renderHostConfig.containerName then
      renderHostConfig.containerName
    else
      "${hostname}-container";

  inventory = globalInventory;

  containerNode =
    if inventory ? realization && inventory.realization ? nodes && lib.hasAttr hostname inventory.realization.nodes then
      inventory.realization.nodes.${hostname}
    else
      abort "container-settings.nix: realization node '${hostname}' missing in inventory.nix";

  containerNodePorts =
    if containerNode ? ports && builtins.isAttrs containerNode.ports then
      containerNode.ports
    else
      abort "container-settings.nix: realization node '${hostname}' is missing ports";

  containerLinks = lib.sort builtins.lessThan (map (p: containerNodePorts.${p}.link) (builtins.attrNames containerNodePorts));

  cpmData = controlPlaneOut.control_plane_model.data or { };

  siteEntries =
    lib.concatMap (
      enterpriseName:
      let
        enterprise = cpmData.${enterpriseName};
      in
      map (siteName: enterprise.${siteName}) (lib.sort builtins.lessThan (builtins.attrNames enterprise))
    ) (lib.sort builtins.lessThan (builtins.attrNames cpmData));

  runtimeTargets =
    lib.foldl' (acc: site: acc // (site.runtimeTargets or { })) { } siteEntries;

  runtimeTargetNames = lib.sort builtins.lessThan (builtins.attrNames runtimeTargets);

  linkNamesForTarget =
    target:
    let
      interfaces = target.effectiveRuntimeRealization.interfaces or { };
    in
    lib.sort builtins.lessThan (
      lib.filter (x: x != null) (
        map (
          ifName:
          let
            iface = interfaces.${ifName};
            backingRef = iface.backingRef or { };
          in
          if (backingRef.kind or null) == "link" then backingRef.name else null
        ) (builtins.attrNames interfaces)
      )
    );

  matchingRuntimeTargets = lib.filter (
    targetName:
    let
      target = runtimeTargets.${targetName};
    in
    builtins.toJSON (linkNamesForTarget target) == builtins.toJSON containerLinks
  ) runtimeTargetNames;

  nodeName =
    if builtins.length matchingRuntimeTargets == 1 then
      builtins.elemAt matchingRuntimeTargets 0
    else if builtins.length matchingRuntimeTargets == 0 then
      abort ''
        container-settings.nix: no runtime target matches container '${hostname}'
        containerLinks: ${builtins.toJSON containerLinks}
      ''
    else
      abort ''
        container-settings.nix: multiple runtime targets match container '${hostname}'
        matches: ${builtins.toJSON matchingRuntimeTargets}
      '';

  renderedContainer = import ./lib/renderer/render-containers.nix {
    inherit lib inventory;
    cpm = controlPlaneOut;
    inherit nodeName hostName;
  };
in
{
  containers.${containerName} = {
    autoStart = true;

    privateNetwork = true;
    hostBridge = null;

    extraVeths = renderedContainer.extraVeths;

    bindMounts."/persist" = {
      hostPath = "/persist";
      isReadOnly = false;
    };

    bindMounts."/run/secrets" = {
      hostPath = "/run/secrets";
      isReadOnly = true;
    };

    bindMounts."/var/lib/containers" = {
      hostPath = "/persist-state/var/lib/containers";
      isReadOnly = false;
    };

    bindMounts."/var/lib/docker" = {
      hostPath = "/persist-state/var/lib/docker";
      isReadOnly = false;
    };

    specialArgs = {
      inherit outPath controlPlaneOut globalInventory;
    };

    config = { controlPlaneOut, globalInventory, ... }: {
      imports = [
        ./container
      ];

      _module.args = {
        inherit controlPlaneOut globalInventory;
      };

      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;
      networking.useHostResolvConf = false;
      services.resolved.enable = lib.mkForce false;

      system.stateVersion = "25.11";
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
      "CAP_NET_RAW"
      "CAP_BPF"
      "CAP_PERFMON"
    ];

    enableTun = true;
  };

  sops.secrets.subnet-ipv6 = { };
}
