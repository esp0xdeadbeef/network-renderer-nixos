{
  lib,
  repoRoot ? ../.,
  flakeInputs ? { },
}:

let
  selectors = import ./host-query.nix { inherit lib; };
  realizationPorts = import ./realization-ports.nix { inherit lib; };

  currentSystem = builtins.currentSystem;

  isControlPlaneLike =
    value:
    builtins.isAttrs value
    && (
      (
        value ? control_plane_model
        && builtins.isAttrs value.control_plane_model
        && value.control_plane_model ? data
        && builtins.isAttrs value.control_plane_model.data
      )
      || (value ? data && builtins.isAttrs value.data)
    );

  buildCompiler =
    {
      intent,
      system ? currentSystem,
    }:
    if
      flakeInputs ? nixos-network-compiler
      && flakeInputs.nixos-network-compiler ? lib
      && flakeInputs.nixos-network-compiler.lib ? compile
    then
      (flakeInputs.nixos-network-compiler.lib.compile system) intent
    else
      throw "lib/api.nix: flake input 'nixos-network-compiler' with lib.compile is required";

  buildForwarding =
    {
      compilerOut,
      system ? currentSystem,
    }:
    if
      flakeInputs ? network-forwarding-model
      && flakeInputs.network-forwarding-model ? lib
      && builtins.hasAttr system flakeInputs.network-forwarding-model.lib
    then
      let
        impl = flakeInputs.network-forwarding-model.lib.${system};
      in
      if builtins.isFunction impl then
        impl { input = compilerOut; }
      else if builtins.isAttrs impl && impl ? build then
        impl.build { input = compilerOut; }
      else
        throw "lib/api.nix: flake input 'network-forwarding-model' has unsupported API shape"
    else if
      flakeInputs ? network-control-plane-model
      && flakeInputs.network-control-plane-model ? lib
      && builtins.hasAttr system flakeInputs.network-control-plane-model.lib
    then
      let
        impl = flakeInputs.network-control-plane-model.lib.${system};
      in
      if builtins.isFunction impl then
        impl { input = compilerOut; }
      else
        throw "lib/api.nix: flake input 'network-control-plane-model' cannot build forwarding output from compiler output"
    else
      throw "lib/api.nix: flake input 'network-forwarding-model' or function-shaped 'network-control-plane-model' is required";

  buildControlPlane =
    {
      forwardingOut,
      inventory,
      system ? currentSystem,
    }:
    if
      flakeInputs ? network-control-plane-model
      && flakeInputs.network-control-plane-model ? lib
      && builtins.hasAttr system flakeInputs.network-control-plane-model.lib
    then
      let
        impl = flakeInputs.network-control-plane-model.lib.${system};
      in
      if builtins.isAttrs impl && impl ? build then
        impl.build {
          input = forwardingOut;
          inherit inventory;
        }
      else if builtins.isFunction impl then
        let
          result = impl { input = forwardingOut; };
        in
        if builtins.isFunction result then result { inherit inventory; } else result
      else if isControlPlaneLike forwardingOut then
        forwardingOut
      else
        throw "lib/api.nix: flake input 'network-control-plane-model' has unsupported API shape"
    else if isControlPlaneLike forwardingOut then
      forwardingOut
    else
      throw "lib/api.nix: flake input 'network-control-plane-model' is required";

  buildCompilerFromPaths =
    {
      intentPath,
      system ? currentSystem,
    }:
    buildCompiler {
      intent = selectors.importMaybeFunction (builtins.toPath intentPath);
      inherit system;
    };

  buildForwardingFromPaths =
    {
      intentPath,
      system ? currentSystem,
    }:
    buildForwarding {
      compilerOut = buildCompilerFromPaths {
        inherit intentPath system;
      };
      inherit system;
    };

  buildControlPlaneFromPaths =
    {
      intentPath,
      inventoryPath,
      system ? currentSystem,
    }:
    buildControlPlane {
      forwardingOut = buildForwardingFromPaths {
        inherit intentPath system;
      };
      inventory = selectors.importMaybeFunction (builtins.toPath inventoryPath);
      inherit system;
    };

  buildAndRenderFromPaths =
    {
      intentPath,
      inventoryPath,
      exampleDir ? null,
      debug ? false,
    }:
    let
      inventory = selectors.importMaybeFunction (builtins.toPath inventoryPath);

      compiler = buildCompilerFromPaths {
        inherit intentPath;
      };

      forwarding = buildForwarding {
        compilerOut = compiler;
      };

      controlPlane = buildControlPlane {
        forwardingOut = forwarding;
        inherit inventory;
      };

      rendered = import ./render-dry-config-output.nix {
        repoRoot = builtins.toString repoRoot;
        cpm = controlPlane;
        inherit exampleDir debug;
      };
    in
    if rendered == null then
      throw ''
        lib/api.nix: buildAndRenderFromPaths produced null render output

        intentPath: ${intentPath}
        inventoryPath: ${inventoryPath}
      ''
    else
      {
        inherit compiler forwarding;
        controlPlane = controlPlane;
        render = rendered;
      };
in
{
  inherit realizationPorts selectors flakeInputs;

  renderer = {
    loadIntent = selectors.importMaybeFunction;
    loadInventory = selectors.importMaybeFunction;
    loadControlPlane = selectors.loadStructuredPath;

    inherit
      buildCompiler
      buildForwarding
      buildControlPlane
      buildCompilerFromPaths
      buildForwardingFromPaths
      buildControlPlaneFromPaths
      buildAndRenderFromPaths
      ;

    renderHostNetwork =
      {
        hostName,
        cpm,
        inventory ? { },
      }:
      import ./render-host-network.nix {
        inherit
          lib
          hostName
          cpm
          inventory
          ;
      };

    renderDryConfig =
      {
        cpmPath,
        exampleDir ? null,
        debug ? false,
      }:
      import ./render-dry-config-output.nix {
        repoRoot = builtins.toString repoRoot;
        inherit cpmPath exampleDir debug;
      };
  };
}
