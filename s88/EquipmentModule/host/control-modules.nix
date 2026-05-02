{ includeValidation ? true }:

[
  ../../Unit/pipeline/fabric-input-loader.nix
  ../../Unit/module/host-network.nix
  ../../Unit/module/container-runtime.nix
]
++ (if includeValidation then [ ../../ControlModule/module/host-validation.nix ] else [ ])
