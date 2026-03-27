{ pkgs, inputs, lib, fabricInputs, globalInventory, ... }:

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
  _module.args.fabricInputs = lib.mkDefault fabricInputs;
  _module.args.globalInventory = lib.mkDefault globalInventory;
  _module.args.compilerOut = compilerOut;
  _module.args.forwardingOut = forwardingOut;
  _module.args.controlPlaneOut = controlPlaneOut;
  _module.args.fabricCompiled = controlPlaneOut;

  environment.etc."network-artifacts/compiler.json".text =
    builtins.toJSON compilerOut;

  environment.etc."network-artifacts/forwarding.json".text =
    builtins.toJSON forwardingOut;

  environment.etc."network-artifacts/control-plane.json".text =
    builtins.toJSON controlPlaneOut;
}
