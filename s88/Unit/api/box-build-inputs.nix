{ lib
, repoPath
, selectors
, buildHostFromControlPlane
, currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux"
,
}:

# NOTE: Path-based discovery of intent.nix/inventory.nix removed (CMC-NIXOS-REMOVE-INTENT-INVENTORY).
# Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume ONLY CPM output.
# Callers must provide pre-built CPM output via the 'cpm' parameter.
# The 'resolvePaths' function and path-based fallback logic have been removed.

let
  resolve =
    { enterpriseName ? null
    , siteName ? null
    , boxName ? null
    , selector ? null
    , cpm ? null
    , inventory ? { }
    , system ? currentSystem
    , file ? "s88/Unit/api/box-build-inputs.nix"
    , ...
    }:
    let
      selectorValue =
        if boxName != null then
          boxName
        else if selector != null then
          selector
        else
          throw ''
            ${file}: requires boxName or selector
          '';

      resolvedCpm =
        if cpm != null then
          cpm
        else
          throw ''
            ${file}: cpm (control plane model) is required.
            Per FS-310-HDS-010-SDS-010-SMS-100, renderers must consume CPM output,
            not discover intent.nix/inventory.nix from disk.
          '';

      builtHost = buildHostFromControlPlane {
        controlPlaneOut = resolvedCpm;
        inherit system file;
        selector = selectorValue;
      };

      matchedSites =
        if builtHost.hostContext ? matchedSites && builtins.isList builtHost.hostContext.matchedSites then
          builtHost.hostContext.matchedSites
        else
          [ ];

      matchedEnterprises =
        if
          builtHost.hostContext ? matchedEnterprises
          && builtins.isList builtHost.hostContext.matchedEnterprises
        then
          builtHost.hostContext.matchedEnterprises
        else
          [ ];

      narrowedHostContext = builtHost.hostContext // {
        hostname = selectorValue;
        matchedSites = if siteName != null then [ siteName ] else matchedSites;
        matchedEnterprises = if enterpriseName != null then [ enterpriseName ] else matchedEnterprises;
        inherit enterpriseName siteName;
      };

      hostPlan = import ../render/host-plan.nix {
        inherit repoPath;
        inherit lib;
        hostName = selectorValue;
        hostContext = narrowedHostContext;
        cpm = builtHost.controlPlaneOut;
        source = builtHost.globalInventory;
      };
    in
    {
      identity = {
        inherit enterpriseName siteName;
        boxName = selectorValue;
      };

      # NOTE: fabric no longer carries intentPath/inventoryPath — removed per SMS-100
      fabric = { };

      inherit
        selectorValue
        builtHost
        hostPlan
        ;

      inherit (builtHost)
        fabricInputs
        globalInventory
        compilerOut
        forwardingOut
        controlPlaneOut
        ;

      hostContext = narrowedHostContext;
    };
in
{
  inherit resolve;
}
