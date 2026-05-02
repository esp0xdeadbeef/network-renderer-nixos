{
  lib,
  selectors,
  buildHostFromPaths,
  currentSystem ? if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux",
}:

let
  resolvePaths =
    {
      outPath ? null,
      fabricRoot ? null,
      intentPath ? null,
      inventoryPath ? null,
      file ? "s88/Unit/api/box-build-inputs.nix",
    }:
    if intentPath != null && inventoryPath != null then
      {
        inherit intentPath inventoryPath;
      }
    else if outPath != null then
      let
        discovered = selectors.pathsFromOutPath {
          inherit outPath fabricRoot;
        };
      in
      {
        intentPath = if intentPath != null then intentPath else discovered.intentPath;
        inventoryPath = if inventoryPath != null then inventoryPath else discovered.inventoryPath;
      }
    else if intentPath != null || inventoryPath != null then
      {
        intentPath =
          if intentPath != null then
            intentPath
          else
            throw ''
              ${file}: intentPath is required when outPath is not provided
            '';

        inventoryPath =
          if inventoryPath != null then
            inventoryPath
          else
            throw ''
              ${file}: inventoryPath is required when outPath is not provided
            '';
      }
    else
      throw ''
        ${file}: requires either outPath or both intentPath and inventoryPath
      '';

  resolve =
    {
      outPath ? null,
      enterpriseName ? null,
      siteName ? null,
      boxName ? null,
      selector ? null,
      fabricRoot ? null,
      intentPath ? null,
      inventoryPath ? null,
      system ? currentSystem,
      file ? "s88/Unit/api/box-build-inputs.nix",
      ...
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

      resolvedPaths = resolvePaths {
        inherit
          outPath
          fabricRoot
          intentPath
          inventoryPath
          file
          ;
      };

      builtHost = buildHostFromPaths {
        inherit system file;
        selector = selectorValue;
        inherit (resolvedPaths) intentPath inventoryPath;
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
        inherit lib;
        hostName = selectorValue;
        hostContext = narrowedHostContext;
        cpm = builtHost.controlPlaneOut;
        inventory = builtHost.globalInventory;
      };
    in
    {
      identity = {
        inherit enterpriseName siteName;
        boxName = selectorValue;
      };

      fabric = {
        inherit (resolvedPaths) intentPath inventoryPath;
      };

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
