{
  lib,
  pkgs,
  ...
}:

let
  input = import ./vm-input-home.nix;

  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";

  renderer = (builtins.getFlake (toString ./.)).libBySystem.${system};

  importValue = import ./src/lookup/import-value.nix { inherit lib; };

  helpers = import ./src/normalize/helpers.nix { inherit lib; };

  normalizeControlPlane = import ./src/normalize/control-plane-output.nix {
    inherit
      lib
      helpers
      ;
  };

  mapHostModel = import ./src/map/host-model.nix { inherit lib; };
  mapBridgeModel = import ./src/map/bridge-model.nix { inherit lib; };
  mapContainerModel = import ./src/map/container-model.nix { inherit lib; };

  renderHostNetwork = import ./src/render/networkd-host.nix { inherit lib; };
  renderBridgeNetwork = import ./src/render/networkd-bridges.nix { inherit lib; };
  renderContainers = import ./src/render/nixos-containers.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  mergeAttrsUnique =
    label: left: right:
    let
      duplicates = lib.filter (name: builtins.hasAttr name right) (sortedAttrNames left);
    in
    if duplicates == [ ] then
      left // right
    else
      throw "vm.nix: duplicate ${label}: ${builtins.toJSON duplicates}";

  primaryInventoryPath = input.inventoryPath;

  resolvedPrimaryInventoryRaw =
    if primaryInventoryPath == null then { } else importValue primaryInventoryPath;

  resolvedPrimaryInventory =
    if builtins.isAttrs resolvedPrimaryInventoryRaw then resolvedPrimaryInventoryRaw else { };

  primaryDeploymentHosts =
    if
      resolvedPrimaryInventory ? deployment
      && builtins.isAttrs resolvedPrimaryInventory.deployment
      && resolvedPrimaryInventory.deployment ? hosts
      && builtins.isAttrs resolvedPrimaryInventory.deployment.hosts
    then
      resolvedPrimaryInventory.deployment.hosts
    else
      { };

  primaryDeploymentHostNames = sortedAttrNames primaryDeploymentHosts;

  requestedBoxName = if input ? boxName then input.boxName else null;

  boxName =
    if requestedBoxName == null || requestedBoxName == "" || requestedBoxName == "*" then
      if builtins.length primaryDeploymentHostNames == 1 then
        builtins.head primaryDeploymentHostNames
      else
        throw "vm.nix: wildcard boxName requires exactly one deployment host in inventory"
    else
      requestedBoxName;

  hostScopedInventoryPath =
    if primaryInventoryPath == null then
      null
    else
      let
        inventoryDir = builtins.dirOf (toString primaryInventoryPath);
        candidate = /. + "${inventoryDir}/${boxName}/inventory.nix";
      in
      if builtins.pathExists candidate then candidate else null;

  effectiveInventoryPath =
    if builtins.hasAttr boxName primaryDeploymentHosts then
      primaryInventoryPath
    else if hostScopedInventoryPath != null then
      hostScopedInventoryPath
    else
      primaryInventoryPath;

  resolvedInventoryRaw =
    if effectiveInventoryPath == null then { } else importValue effectiveInventoryPath;

  resolvedInventory = if builtins.isAttrs resolvedInventoryRaw then resolvedInventoryRaw else { };

  inventoryDeploymentHosts =
    if
      resolvedInventory ? deployment
      && builtins.isAttrs resolvedInventory.deployment
      && resolvedInventory.deployment ? hosts
      && builtins.isAttrs resolvedInventory.deployment.hosts
    then
      resolvedInventory.deployment.hosts
    else
      { };

  controlPlaneOut = renderer.renderer.buildControlPlaneFromPaths {
    intentPath = input.intentPath;
    inventoryPath = effectiveInventoryPath;
  };

  normalizedModel = normalizeControlPlane controlPlaneOut;

  normalizedDeploymentHosts =
    if normalizedModel ? deploymentHosts && builtins.isAttrs normalizedModel.deploymentHosts then
      normalizedModel.deploymentHosts
    else
      { };

  deploymentHostDef =
    if builtins.hasAttr boxName inventoryDeploymentHosts then
      inventoryDeploymentHosts.${boxName}
    else if builtins.hasAttr boxName normalizedDeploymentHosts then
      normalizedDeploymentHosts.${boxName}
    else
      throw "vm.nix: deployment host '${boxName}' is missing from inventory and normalized control-plane output";

  inventoryRenderHosts =
    if
      resolvedInventory ? render
      && builtins.isAttrs resolvedInventory.render
      && resolvedInventory.render ? hosts
      && builtins.isAttrs resolvedInventory.render.hosts
    then
      resolvedInventory.render.hosts
    else
      { };

  normalizedRenderHosts =
    if normalizedModel ? renderHosts && builtins.isAttrs normalizedModel.renderHosts then
      normalizedModel.renderHosts
    else
      { };

  renderHosts = if inventoryRenderHosts != { } then inventoryRenderHosts else normalizedRenderHosts;

  selectedRenderHostNames =
    let
      renderHostNames = sortedAttrNames renderHosts;
      selectedNames = lib.filter (
        renderHostName:
        let
          cfg = renderHosts.${renderHostName};
          deploymentTarget =
            if builtins.isAttrs cfg && cfg ? deploymentHost && builtins.isString cfg.deploymentHost then
              cfg.deploymentHost
            else
              renderHostName;
        in
        deploymentTarget == boxName
      ) renderHostNames;
    in
    if selectedNames == [ ] then [ boxName ] else selectedNames;

  artifactModule = renderer.artifacts.controlPlaneSplitFromControlPlane {
    inherit controlPlaneOut;
    fileName = "control-plane-model.json";
    directory = "network-artifacts";
  };

  renderedHost = renderHostNetwork (mapHostModel {
    inherit boxName deploymentHostDef;
  });

  renderedBridges = renderBridgeNetwork (mapBridgeModel {
    inherit boxName deploymentHostDef;
  });

  renderedContainersByRenderHost = builtins.listToAttrs (
    map (renderHostName: {
      name = renderHostName;
      value = renderContainers (mapContainerModel {
        model = normalizedModel;
        boxName = renderHostName;
        inherit deploymentHostDef;
        defaults = {
          autoStart = true;
          privateNetwork = true;
        };
      });
    }) selectedRenderHostNames
  );

  renderedContainers = lib.foldl' (
    acc: renderHostName:
    mergeAttrsUnique "containers" acc renderedContainersByRenderHost.${renderHostName}
  ) { } selectedRenderHostNames;

  renderedNetdevs = mergeAttrsUnique "systemd.network.netdevs" (renderedHost.netdevs or { }) (
    renderedBridges.netdevs or { }
  );

  renderedNetworks = mergeAttrsUnique "systemd.network.networks" (renderedHost.networks or { }) (
    renderedBridges.networks or { }
  );
in
{
  imports = [ artifactModule ];

  assertions = [
    {
      assertion = input.intentPath != null;
      message = "vm-input.nix requires intentPath";
    }
    {
      assertion = input.inventoryPath != null;
      message = "vm-input.nix requires inventoryPath";
    }
    {
      assertion = boxName != null;
      message = "vm-input.nix requires a resolved boxName";
    }
  ];

  system.stateVersion = "25.11";

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.netdevs = renderedNetdevs;
  systemd.network.networks = renderedNetworks;

  boot.enableContainers = true;
  containers = renderedContainers;

  systemd.services."container@" = {
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
  };

  networking.useDHCP = true;
  services.resolved.enable = true;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };

  boot.kernelModules = [ "br_netfilter" ];

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    containerlab
    iproute2
    jq
    gron
    tmux
    neovim
    tcpdump
    traceroute
    nftables
  ];

  networking.nftables.enable = true;

  users.users.root.shell = pkgs.bash;

  virtualisation.memorySize = 1024 * 24;
  virtualisation.cores = 22;
  environment.etc.hosts.enable = false;
  services.openssh.enable = true;

  nixos-shell.mounts = {
    cache = "none";
  };
}
