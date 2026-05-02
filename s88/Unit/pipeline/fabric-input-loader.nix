{
  config,
  pkgs,
  inputs,
  fabricInputs,
  globalInventory,
  hostContext ? { },
  lib,
  ...
}:

let
  renderer = inputs.network-renderer-nixos.lib.renderer;
  runtimeContext = import ../lookup/runtime-context.nix { inherit lib; };

  system = pkgs.stdenv.hostPlatform.system;

  compilerOut = renderer.buildCompiler {
    intent = fabricInputs;
    inherit system;
  };

  forwardingOut = renderer.buildForwarding {
    inherit compilerOut system;
  };

  controlPlaneOut = renderer.buildControlPlane {
    inherit forwardingOut system;
    inventory = globalInventory;
  };

  requestedHostName =
    if hostContext ? hostname && builtins.isString hostContext.hostname then
      hostContext.hostname
    else
      config.networking.hostName;

  renderedHostNetwork = renderer.renderHostNetwork {
    hostName = requestedHostName;
    inherit hostContext;
    cpm = controlPlaneOut;
    inventory = globalInventory;
  };

  _validatedRuntimeTargets = runtimeContext.validateAllRuntimeTargets {
    cpm = controlPlaneOut;
    inventory = globalInventory;
    file = "s88/Unit/pipeline/fabric-input-loader.nix";
  };
in
{
  _module.args = {
    inherit
      compilerOut
      forwardingOut
      controlPlaneOut
      renderedHostNetwork
      ;
    fabricCompiled = controlPlaneOut;
  };

  environment.etc."network-artifacts/compiler.json".text = builtins.toJSON compilerOut;

  environment.etc."network-artifacts/forwarding.json".text = builtins.toJSON forwardingOut;

  environment.etc."network-artifacts/control-plane.json".text = builtins.toJSON controlPlaneOut;
}
