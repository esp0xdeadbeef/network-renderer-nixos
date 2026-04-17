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

  normalizeCommunicationContract = import ./src/normalize/communication-contract.nix {
    inherit lib;
  };

  normalizeControlPlane = import ./src/normalize/control-plane-output.nix {
    inherit
      lib
      helpers
      ;
  };

  lookupSiteServiceInputs = import ./src/lookup/site-service-inputs.nix {
    inherit lib;
  };

  mapFirewallForwardingRuntimeTargetModel =
    import ./src/map/firewall-forwarding-runtime-target-model.nix
      { inherit lib; };

  mapFirewallPolicyRuntimeTargetModel = import ./src/map/firewall-policy-runtime-target-model.nix {
    inherit
      lib
      normalizeCommunicationContract
      lookupSiteServiceInputs
      ;
  };

  selectFirewallRuntimeTargetModel = import ./src/policy/select-firewall-runtime-target-model.nix {
    inherit
      lib
      lookupSiteServiceInputs
      mapFirewallForwardingRuntimeTargetModel
      mapFirewallPolicyRuntimeTargetModel
      ;
  };

  mapKeaRuntimeTargetServiceModel = import ./src/map/kea-runtime-target-service-model.nix {
    inherit lib;
  };

  mapRadvdRuntimeTargetServiceModel = import ./src/map/radvd-runtime-target-service-model.nix {
    inherit lib;
  };

  selectContainerRuntimeTargetServiceModels =
    import ./src/policy/select-container-runtime-target-service-models.nix
      {
        inherit
          lib
          mapKeaRuntimeTargetServiceModel
          mapRadvdRuntimeTargetServiceModel
          ;
      };

  renderNftablesRuntimeTarget = import ./src/render/nftables-runtime-target.nix { inherit lib; };

  mapContainerRuntimeArtifactModel = import ./src/map/container-runtime-artifact-model.nix {
    inherit
      lib
      selectFirewallRuntimeTargetModel
      renderNftablesRuntimeTarget
      selectContainerRuntimeTargetServiceModels
      ;
  };

  mapVmContainerSimulatedModel = import ./src/map/vm-container-simulated-model.nix {
    inherit
      lib
      mapContainerRuntimeArtifactModel
      ;
  };

  mapVmSimulatedHostBridgeModel = import ./src/map/vm-simulated-host-bridge-model.nix {
    inherit lib;
  };

  mapHostModel = import ./src/map/host-model.nix { inherit lib; };
  mapBridgeModel = import ./src/map/bridge-model.nix { inherit lib; };

  renderHost = import ./src/render/networkd-host.nix { inherit lib; };
  renderBridges = import ./src/render/networkd-bridges.nix { inherit lib; };
  renderContainers = import ./src/render/nixos-containers.nix { inherit lib; };
  renderSimulatedBridges = import ./src/render/networkd-simulated-bridges.nix { inherit lib; };

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

  resolvedEffectiveInventoryRaw =
    if effectiveInventoryPath == null then { } else importValue effectiveInventoryPath;

  resolvedEffectiveInventory =
    if builtins.isAttrs resolvedEffectiveInventoryRaw then resolvedEffectiveInventoryRaw else { };

  effectiveDeploymentHosts =
    if
      resolvedEffectiveInventory ? deployment
      && builtins.isAttrs resolvedEffectiveInventory.deployment
      && resolvedEffectiveInventory.deployment ? hosts
      && builtins.isAttrs resolvedEffectiveInventory.deployment.hosts
    then
      resolvedEffectiveInventory.deployment.hosts
    else
      { };

  effectiveDeploymentHostNames = sortedAttrNames effectiveDeploymentHosts;

  resolvedDeploymentHostName =
    if builtins.hasAttr boxName effectiveDeploymentHosts then
      boxName
    else if builtins.length effectiveDeploymentHostNames == 1 then
      builtins.head effectiveDeploymentHostNames
    else
      throw ''
        vm.nix: could not resolve deployment host '${boxName}' from effective inventory
        effectiveInventoryPath=${toString effectiveInventoryPath}
        knownDeploymentHosts=${builtins.toJSON effectiveDeploymentHostNames}
      '';

  deploymentHostDef = effectiveDeploymentHosts.${resolvedDeploymentHostName};

  hostControlPlaneOut = renderer.renderer.buildControlPlaneFromPaths {
    intentPath = input.intentPath;
    inventoryPath = effectiveInventoryPath;
  };

  simulatedControlPlaneOut = renderer.renderer.buildControlPlaneFromPaths {
    intentPath = input.intentPath;
    inventoryPath = primaryInventoryPath;
  };

  simulatedNormalizedModel = normalizeControlPlane simulatedControlPlaneOut;

  hostRendered = renderHost (mapHostModel {
    boxName = resolvedDeploymentHostName;
    inherit deploymentHostDef;
  });

  bridgeRendered = renderBridges (mapBridgeModel {
    boxName = resolvedDeploymentHostName;
    inherit deploymentHostDef;
  });

  simulatedContainerModel = mapVmContainerSimulatedModel {
    normalizedModel = simulatedNormalizedModel;
    deploymentHostName = resolvedDeploymentHostName;
    defaults = {
      autoStart = true;
      privateNetwork = true;
    };
  };

  simulatedBridgeRendered = renderSimulatedBridges (mapVmSimulatedHostBridgeModel {
    containerModel = simulatedContainerModel;
    deploymentHostName = resolvedDeploymentHostName;
  });

  renderedContainers = renderContainers simulatedContainerModel;

  renderedNetdevs = mergeAttrsDedupe "systemd.network.netdevs" (mergeAttrsDedupe
    "systemd.network.netdevs"
    (hostRendered.netdevs or { })
    (bridgeRendered.netdevs or { })
  ) (simulatedBridgeRendered.netdevs or { });

  renderedNetworks = mergeAttrsDedupe "systemd.network.networks" (mergeAttrsDedupe
    "systemd.network.networks"
    (hostRendered.networks or { })
    (bridgeRendered.networks or { })
  ) (simulatedBridgeRendered.networks or { });

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
