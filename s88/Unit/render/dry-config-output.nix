{ repoRoot
, lib ? null
, renderer ? null
, cpm ? null
, cpmPath ? null
, source ? { }
, exampleDir ? null
, debug ? false
,
}:

let
  flake =
    if lib == null || renderer == null then
      builtins.getFlake (toString (builtins.toPath repoRoot))
    else
      null;

  resolvedLib =
    if lib != null then
      lib
    else if
      flake != null
      && flake ? lib
      && flake.lib ? flakeInputs
      && flake.lib.flakeInputs ? nixpkgs
      && flake.lib.flakeInputs.nixpkgs ? lib
    then
      flake.lib.flakeInputs.nixpkgs.lib
    else
      throw "s88/Unit/render/dry-config-output.nix: unable to resolve nixpkgs lib from flake inputs";

  resolvedRenderer =
    if renderer != null then
      renderer
    else if flake != null && flake ? lib && flake.lib ? renderer then
      flake.lib.renderer
    else
      throw "s88/Unit/render/dry-config-output.nix: unable to resolve renderer API";

  runtimeContext = import ../lookup/runtime-context.nix { lib = resolvedLib; };
  runtimeTargets = import ../mapping/runtime-targets.nix { lib = resolvedLib; };

  renderInputs = import ../../ControlModule/lookup/render-inputs.nix {
    lib = resolvedLib;
    renderer = resolvedRenderer;
    inherit repoRoot cpm cpmPath source exampleDir;
  };

  controlPlane = renderInputs.controlPlane;
  resolvedInventory = renderInputs.resolvedInventory;
  metadataSourcePaths = renderInputs.metadataSourcePaths;

  sortedAttrNames = attrs: resolvedLib.sort builtins.lessThan (builtins.attrNames attrs);

  _validateRuntimeTargets = runtimeContext.validateAllRuntimeTargets {
    cpm = controlPlane;
    source = resolvedInventory;
    file = "s88/Unit/render/dry-config-output.nix";
  };

  normalizedRuntimeTargets = runtimeTargets.normalizedRuntimeTargets {
    cpm = controlPlane;
    file = "s88/Unit/render/dry-config-output.nix";
  };

  unitNames = sortedAttrNames normalizedRuntimeTargets;

  deploymentHostNames = resolvedLib.sort builtins.lessThan (
    resolvedLib.unique (
      map
        (
          unitName:
          runtimeContext.deploymentHostForUnit {
            cpm = controlPlane;
            source = resolvedInventory;
            inherit unitName;
            file = "s88/Unit/render/dry-config-output.nix";
          }
        )
        unitNames
    )
  );

  hostRenderings = builtins.listToAttrs (
    map
      (hostName: {
        name = hostName;
        value = resolvedRenderer.renderHostNetwork {
          inherit hostName;
          cpm = controlPlane;
          source = resolvedInventory;
        };
      })
      deploymentHostNames
  );

  output = import ../../ControlModule/render/dry-config-model.nix {
    lib = resolvedLib;
    inherit
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
