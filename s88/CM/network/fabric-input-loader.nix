{ pkgs, inputs, fabricInputs, globalInventory, lib, ... }:

let
  runtimeContext = import ../../../lib/runtime-context.nix { inherit lib; };

  system = pkgs.stdenv.hostPlatform.system;

  compilerOut =
    (inputs.nixos-network-compiler.lib.compile system) fabricInputs;

  forwardingOut =
    inputs.network-forwarding-model.lib.${system} {
      input = compilerOut;
    };

  controlPlaneOut =
    inputs.network-control-plane-model.lib.${system}.build {
      input = forwardingOut;
      inventory = globalInventory;
    };

  _validatedRuntimeTargets =
    runtimeContext.validateAllRuntimeTargets {
      cpm = controlPlaneOut;
      inventory = globalInventory;
      file = "s88/CM/network/fabric-input-loader.nix";
    };
in
{
  _module.args = {
    inherit compilerOut forwardingOut controlPlaneOut;
    fabricCompiled = controlPlaneOut;
  };

  environment.etc."network-artifacts/compiler.json".text =
    builtins.toJSON compilerOut;

  environment.etc."network-artifacts/forwarding.json".text =
    builtins.toJSON forwardingOut;

  environment.etc."network-artifacts/control-plane.json".text =
    builtins.toJSON controlPlaneOut;
}
