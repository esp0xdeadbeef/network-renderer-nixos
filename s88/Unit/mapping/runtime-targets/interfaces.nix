{ lib }:

let
  runtimeContext = import ../../lookup/runtime-context.nix { inherit lib; };
  forwarding = import ./forwarding.nix { inherit lib; };
  common = import ./interfaces/common.nix { inherit lib; };
  renderedNames = import ./interfaces/rendered-names.nix {
    inherit lib runtimeContext common;
  };
  hostBridge = import ./interfaces/host-bridge.nix { inherit lib common; };
  normalize = import ./interfaces/normalize.nix {
    inherit lib runtimeContext forwarding common renderedNames hostBridge;
  };
in
{
  inherit (normalize)
    emittedInterfacesForUnit
    emittedLoopbackForUnit
    normalizedInterfaceForUnit
    normalizedInterfacesForUnit
    ;
  inherit (renderedNames) desiredRenderedIfNameForInterface renderedInterfaceNamesForUnit;
  inherit (hostBridge) hostBridgeIdentityForInterface;
}
