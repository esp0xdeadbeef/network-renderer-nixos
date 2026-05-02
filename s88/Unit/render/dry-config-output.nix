{
  repoRoot,
  cpm ? null,
  cpmPath ? null,
  inventory ? { },
  inventoryPath ? null,
  exampleDir ? null,
  debug ? false,
}:

let
  flake = builtins.getFlake (toString (builtins.toPath repoRoot));

  lib =
    if
      flake ? lib
      && flake.lib ? flakeInputs
      && flake.lib.flakeInputs ? nixpkgs
      && flake.lib.flakeInputs.nixpkgs ? lib
    then
      flake.lib.flakeInputs.nixpkgs.lib
    else
      throw "s88/Unit/render/dry-config-output.nix: unable to resolve nixpkgs lib from flake inputs";

  renderer = flake.lib.renderer;

  runtimeContext = import ../lookup/runtime-context.nix { inherit lib; };
  runtimeTargets = import ../mapping/runtime-targets.nix { inherit lib; };

  renderInputs = import ../../ControlModule/lookup/render-inputs.nix {
    inherit
      lib
      renderer
      repoRoot
      cpm
      cpmPath
      inventory
      inventoryPath
      exampleDir
      ;
  };

  controlPlane = renderInputs.controlPlane;
  resolvedInventory = renderInputs.resolvedInventory;
  metadataSourcePaths = renderInputs.metadataSourcePaths;

  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  _validateRuntimeTargets = runtimeContext.validateAllRuntimeTargets {
    cpm = controlPlane;
    inventory = resolvedInventory;
    file = "s88/Unit/render/dry-config-output.nix";
  };

  normalizedRuntimeTargets = runtimeTargets.normalizedRuntimeTargets {
    cpm = controlPlane;
    file = "s88/Unit/render/dry-config-output.nix";
  };

  unitNames = sortedAttrNames normalizedRuntimeTargets;

  deploymentHostNames = lib.sort builtins.lessThan (
    lib.unique (
      map (
        unitName:
        runtimeContext.deploymentHostForUnit {
          cpm = controlPlane;
          inventory = resolvedInventory;
          inherit unitName;
          file = "s88/Unit/render/dry-config-output.nix";
        }
      ) unitNames
    )
  );

  hostRenderings = builtins.listToAttrs (
    map (hostName: {
      name = hostName;
      value = renderer.renderHostNetwork {
        inherit hostName;
        cpm = controlPlane;
        inventory = resolvedInventory;
      };
    }) deploymentHostNames
  );

  output = import ./dry-config-model.nix {
    inherit
      lib
      metadataSourcePaths
      runtimeContext
      normalizedRuntimeTargets
      hostRenderings
      deploymentHostNames
      controlPlane
      resolvedInventory
      ;
    debugEnabled = debug;
  };

  validation = builtins.seq _validateRuntimeTargets (
    if unitNames == [ ] then
      throw ''
        s88/Unit/render/dry-config-output.nix: no runtime targets found in control-plane model
      ''
    else if deploymentHostNames == [ ] then
      throw ''
        s88/Unit/render/dry-config-output.nix: no deployment hosts found in control-plane model
      ''
    else if
      output.render.hosts == { } && output.render.nodes == { } && output.render.containers == { }
    then
      throw ''
        s88/Unit/render/dry-config-output.nix: empty render output
      ''
    else
      true
  );
in
builtins.seq validation output
