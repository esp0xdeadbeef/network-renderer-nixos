{ ... }:

{
  imports = [
    ../../ControlModule/pipeline/fabric-input-loader.nix
    ../../ControlModule/module/host-network.nix
    ../../ControlModule/module/container-runtime.nix
  ];
}
