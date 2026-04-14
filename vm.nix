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

  mapVmContainerSimulatedModel = import ./src/map/vm-container-simulated-model.nix { inherit lib; };

  renderContainers = import ./src/render/nixos-containers.nix { inherit lib; };

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  json = value: builtins.toJSON value;

  mergeAttrsDedupe =
    label: left: right:
    let
      names = lib.unique (sortedAttrNames left ++ sortedAttrNames right);
    in
    builtins.listToAttrs (
      map (
        name:
        if !(builtins.hasAttr name left) then
          {
            inherit name;
            value = right.${name};
          }
        else if !(builtins.hasAttr name right) then
          {
            inherit name;
            value = left.${name};
          }
        else if json left.${name} == json right.${name} then
          {
            inherit name;
            value = left.${name};
          }
        else
          throw "vm.nix: conflicting ${label} for '${name}'"
      ) names
    );

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

  hostControlPlaneOut = renderer.renderer.buildControlPlaneFromPaths {
    intentPath = input.intentPath;
    inventoryPath = effectiveInventoryPath;
  };

  simulatedControlPlaneOut = renderer.renderer.buildControlPlaneFromPaths {
    intentPath = input.intentPath;
    inventoryPath = primaryInventoryPath;
  };

  simulatedNormalizedModel = normalizeControlPlane simulatedControlPlaneOut;

  hostRendered = renderer.host.buildFromControlPlane {
    controlPlaneOut = hostControlPlaneOut;
    inherit boxName;
  };

  bridgeRendered = renderer.bridges.buildFromControlPlane {
    controlPlaneOut = hostControlPlaneOut;
    inherit boxName;
  };

  renderedContainers = renderContainers (mapVmContainerSimulatedModel {
    normalizedModel = simulatedNormalizedModel;
    deploymentHostName = boxName;
    defaults = {
      autoStart = true;
      privateNetwork = true;
    };
  });

  renderedNetdevs = mergeAttrsDedupe "systemd.network.netdevs" (hostRendered.netdevs or { }) (
    bridgeRendered.netdevs or { }
  );

  renderedNetworks = mergeAttrsDedupe "systemd.network.networks" (hostRendered.networks or { }) (
    bridgeRendered.networks or { }
  );

  artifactModule = renderer.artifacts.controlPlaneSplitFromControlPlane {
    controlPlaneOut = simulatedControlPlaneOut;
    fileName = "control-plane-model.json";
    directory = "network-artifacts";
  };
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
