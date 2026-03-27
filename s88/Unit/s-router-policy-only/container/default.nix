{
  lib,
  pkgs,
  outPath,
  controlPlaneOut,
  globalInventory,
  rendererHostName,
  runtimeUnitName,
  ...
}:

let
  hostname = runtimeUnitName;

  inventory = globalInventory;

  runtimeContext = import "${outPath}/lib/runtime-context.nix" { inherit lib; };

  listInvariants = import ../lib/list-invariants.nix { inherit lib; };
  inherit (listInvariants) duplicates;

  stripPrefix =
    addr:
    let
      parts = lib.splitString "/" addr;
    in
    if parts == [ ] then
      addr
    else
      builtins.head parts;

  containerNode =
    if inventory ? realization && inventory.realization ? nodes && lib.hasAttr rendererHostName inventory.realization.nodes then
      inventory.realization.nodes.${rendererHostName}
    else
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: realization node missing in inventory.nix
      '';

  containerNodePorts =
    if containerNode ? ports && builtins.isAttrs containerNode.ports then
      containerNode.ports
    else
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: realization node ports missing
      '';

  containerLinks =
    lib.sort builtins.lessThan (map (p: containerNodePorts.${p}.link) (builtins.attrNames containerNodePorts));

  selectedSite = runtimeContext.siteEntryForUnit {
    cpm = controlPlaneOut;
    unitName = runtimeUnitName;
    file = "s88/Unit/s-router-policy-only/container/default.nix";
  };

  preferredSource4 =
    if selectedSite.site ? topology
      && builtins.isAttrs selectedSite.site.topology
      && selectedSite.site.topology ? nodes
      && builtins.isAttrs selectedSite.site.topology.nodes
      && builtins.hasAttr runtimeUnitName selectedSite.site.topology.nodes
      && selectedSite.site.topology.nodes.${runtimeUnitName} ? loopback
      && selectedSite.site.topology.nodes.${runtimeUnitName}.loopback ? ipv4
    then
      stripPrefix selectedSite.site.topology.nodes.${runtimeUnitName}.loopback.ipv4
    else
      null;

  runtimeTargetName = runtimeUnitName;

  runtimeTarget = runtimeContext.runtimeTargetForUnit {
    cpm = controlPlaneOut;
    unitName = runtimeTargetName;
    file = "s88/Unit/s-router-policy-only/container/default.nix";
  };

  runtimeRealization =
    if runtimeTarget ? effectiveRuntimeRealization then
      runtimeTarget.effectiveRuntimeRealization
    else
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: effectiveRuntimeRealization missing
      '';

  runtimeIfaces =
    if runtimeRealization ? interfaces then
      runtimeRealization.interfaces
    else
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interfaces missing
      '';

  topoIfaceForRuntime = import ../lib/renderer/topology.nix {
    inherit lib hostname;
  };

  topoDetails =
    map
      (
        name:
        (topoIfaceForRuntime name runtimeIfaces.${name})
        // {
          inherit preferredSource4;
        }
      )
      (lib.sort builtins.lessThan (builtins.attrNames runtimeIfaces));

  ifaceLinks = map (d: d.linkName) (lib.filter (d: d.linkName != null) topoDetails);
  ifaceNames = map (d: d.renderedIfName) topoDetails;

  _uniqueRuntimeInterfaceLinks =
    let
      dup = duplicates ifaceLinks;
    in
    if dup != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate runtime interface links
        duplicateLinks: ${builtins.toJSON dup}
      ''
    else
      true;

  _uniqueRuntimeInterfaceNames =
    let
      dup = duplicates ifaceNames;
    in
    if dup != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate rendered interface names
        duplicateNames: ${builtins.toJSON dup}
      ''
    else
      true;

  _linkCoverage =
    let
      missingLinks = lib.filter (linkName: !(builtins.elem linkName containerLinks)) ifaceLinks;
      extraLinks = lib.filter (linkName: !(builtins.elem linkName ifaceLinks)) containerLinks;
    in
    if missingLinks != [ ] || extraLinks != [ ] then
      abort ''
        renderer/container/default.nix
        hostname: ${rendererHostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interface to realization node link coverage mismatch
        missingLinks: ${builtins.toJSON missingLinks}
        extraLinks: ${builtins.toJSON extraLinks}
      ''
    else
      true;

  mkNetwork = import ../lib/renderer/network.nix { inherit lib; };

  renderedNetworks = builtins.listToAttrs (map mkNetwork topoDetails);

  debugArtifacts = {
    "network-artifacts/container-runtime-target-name.txt".text = runtimeTargetName;

    "network-artifacts/container-runtime-realization.json".text =
      builtins.toJSON runtimeRealization;

    "network-artifacts/container-rendered-networks.json".text =
      builtins.toJSON renderedNetworks;

    "network-artifacts/control-plane.json".text =
      builtins.toJSON controlPlaneOut;
  };
in
{
  imports = [
    ./debugging-packages.nix
    ./nftables.nix
  ];

  networking.hostName = hostname;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = false;

  networking.firewall.enable = false;
  services.resolved.enable = false;

  boot.isContainer = true;

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = lib.mkDefault 1;
    "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    "net.ipv6.conf.default.forwarding" = lib.mkDefault 1;
    "net.ipv4.conf.all.rp_filter" = lib.mkDefault 0;
    "net.ipv4.conf.default.rp_filter" = lib.mkDefault 0;
  };

  systemd.network.networks = lib.mkForce renderedNetworks;

  environment.etc = debugArtifacts;

  system.activationScripts.networkArtifactsDebug = lib.stringAfter [ "etc" ] ''
    mkdir -p /etc/network-artifacts
    printf '%s\n' '${runtimeTargetName}' > /etc/network-artifacts/container-runtime-target-name.txt
    cp -f ${pkgs.writeText "container-runtime-realization.json" (builtins.toJSON runtimeRealization)} /etc/network-artifacts/container-runtime-realization.json
    cp -f ${pkgs.writeText "container-rendered-networks.json" (builtins.toJSON renderedNetworks)} /etc/network-artifacts/container-rendered-networks.json
    cp -f ${pkgs.writeText "control-plane.json" (builtins.toJSON controlPlaneOut)} /etc/network-artifacts/control-plane.json
  '';

  system.stateVersion = "25.11";
}
