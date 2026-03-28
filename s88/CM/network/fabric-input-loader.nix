{ pkgs, inputs, fabricInputs, globalInventory, lib, ... }:

let
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
