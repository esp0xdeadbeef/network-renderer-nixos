{ lib ? null
, selectors
, buildHostFromControlPlane
,
}:

# NOTE: This module previously accepted outPath and discovered intent.nix/inventory.nix
# from disk via pathsFromOutPath. Per FS-310-HDS-010-SDS-010-SMS-100, renderers must
# consume ONLY CPM output. The renderer now requires pre-built CPM output.
#
# Callers must provide:
#   cpm: control plane model output
#   inventory: inventory data (may be {})
# These should be built by a pipeline harness (compiler→NFM→CPM) OUTSIDE the renderer.

{ lib ? null
, system ? "x86_64-linux"
, hostName
, cpm ? null
, controlPlane ? null
, compilerOut ? null
, forwardingOut ? null
, source ? { }
, selectorFile ? "s88/Unit/api/module-host-build.nix"
, containerDefaults ? { }
, disabled ? { }
, containerSelection ? { }
  # FS-310-HDS-040-SDS-010-SMS-101: runtimeFacts carry NON-AUTHORITATIVE
  # runtime facts only (e.g. publicIngress bridge interface, SNAT source
  # CIDR, runtime forward facts). Policy authority — which public-ingress
  # tuples may materialize firewall/DNAT output — comes exclusively from the
  # CPM artifact. A policy-bearing runtime fact with no corresponding CPM
  # authority fails closed (RENDERER_LOCAL_POLICY_AUTHORITY).
, runtimeFacts ? { }
,
}:

let
  effectiveLib =
    if lib != null then
      lib
    else
      throw ''
        s88/Unit/api/module-host-build.nix: lib is required
      '';

  # Require CPM output — renderer no longer discovers intent/inventory from disk
  resolvedCpm =
    if cpm != null then
      cpm
    else if controlPlane != null then
      controlPlane
    else
      throw ''
        s88/Unit/api/module-host-build.nix: cpm or controlPlane (control plane model) is required.
        Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume CPM output,
        not discover intent.nix/inventory.nix from disk.
        Provide pre-built CPM output via the 'cpm' or 'controlPlane' parameter.
      '';

  resolvedCompilerOut =
    if compilerOut != null then
      compilerOut
    else if builtins.isAttrs resolvedCpm && resolvedCpm ? compilerOut then
      resolvedCpm.compilerOut
    else
      { };

  resolvedForwardingOut =
    if forwardingOut != null then
      forwardingOut
    else if builtins.isAttrs resolvedCpm && resolvedCpm ? forwardingOut then
      resolvedCpm.forwardingOut
    else
      { };

  builtHost = buildHostFromControlPlane {
    controlPlaneOut = resolvedCpm;
    compilerOut = resolvedCompilerOut;
    forwardingOut = resolvedForwardingOut;
    inherit source;
    selector = hostName;
    inherit
      system
      containerDefaults
      disabled
      ;
    file = selectorFile;
  };

  selectedContainers = import ../../ControlModule/api/container-selection.nix {
    lib = effectiveLib;
    inherit
      containerSelection
      ;
    containers = builtHost.renderedHost.containers or { };
  };

  renderedHostNetwork = builtHost.renderedHost // {
    containers = selectedContainers;
  };

  debugPayload = import ../../ControlModule/api/debug-payload.nix {
    lib = effectiveLib;
    inherit
      system
      hostName
      renderedHostNetwork
      ;
    hostContext = builtHost.hostContext;
    intent = builtHost.fabricInputs;
    globalInventory = builtHost.globalInventory;
    compilerOut = builtHost.compilerOut;
    forwardingOut = builtHost.forwardingOut;
    controlPlaneOut = builtHost.controlPlaneOut;
    # intentPath/inventoryPath no longer passed — removed per SMS-100
  };

  artifactModule = import ../../ControlModule/api/artifact-module.nix { inherit debugPayload; };

  # FS-310-HDS-040-SDS-010-SMS-101: the production host entry is the CPM-only
  # consumption boundary for policy-bearing public-ingress output. The
  # public-ingress module receives the resolved CPM artifact as its sole
  # policy authority; runtimeFacts supply runtime facts only. Rendering
  # public-ingress output outside this entry (direct helper import with
  # synthetic facts) is renderer-local policy injection and is rejected by
  # the module itself (RENDERER_LOCAL_POLICY_AUTHORITY).
  publicIngressModule =
    { pkgs, ... }:
    import ../../ControlModule/module/public-ingress.nix {
      lib = effectiveLib;
      inherit pkgs hostName runtimeFacts;
      controlPlane = resolvedCpm;
    };

  moduleArgs = {
    globalInventory = builtHost.globalInventory;
    hostContext = builtHost.hostContext;
    intent = builtHost.fabricInputs;
    fabricInputs = builtHost.fabricInputs;
    compilerOut = builtHost.compilerOut;
    forwardingOut = builtHost.forwardingOut;
    controlPlaneOut = builtHost.controlPlaneOut;
    inherit renderedHostNetwork;
  };
in
{
  inherit renderedHostNetwork debugPayload;

  inherit artifactModule moduleArgs;

  nixosModule = {
    imports = [
      artifactModule
      publicIngressModule
    ];

    _module.args = moduleArgs;

    networking.useNetworkd = true;
    systemd.network.enable = true;
    networking.useDHCP = false;
    networking.useHostResolvConf = effectiveLib.mkForce false;

    systemd.network.netdevs = renderedHostNetwork.netdevs or { };
    systemd.network.networks = renderedHostNetwork.networks or { };
    containers = renderedHostNetwork.containers or { };
  };
}
