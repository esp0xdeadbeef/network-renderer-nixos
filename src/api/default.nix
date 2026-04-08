{ lib, controlPlaneLib }:
let
  importValue = import ../lookup/import-value.nix { inherit lib; };

  buildControlPlaneOutput = import ../lookup/control-plane-output.nix {
    inherit
      lib
      controlPlaneLib
      importValue
      ;
  };

  helpers = import ../normalize/helpers.nix { inherit lib; };

  normalizeControlPlane = import ../normalize/control-plane-output.nix {
    inherit
      lib
      helpers
      ;
  };

  selectDeploymentHost = import ../policy/select-deployment-host.nix { inherit lib; };
  selectRenderHost = import ../policy/select-render-host.nix { inherit lib; };

  mapHostModel = import ../map/host-model.nix { inherit lib; };
  mapBridgeModel = import ../map/bridge-model.nix { inherit lib; };
  mapContainerModel = import ../map/container-model.nix { inherit lib; };

  renderHostNetwork = import ../render/networkd-host.nix { inherit lib; };
  renderBridgeNetwork = import ../render/networkd-bridges.nix { inherit lib; };
  renderContainers = import ../render/nixos-containers.nix { inherit lib; };
in
{
  renderer = import ./renderer.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      ;
  };

  host = import ./host.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapHostModel
      renderHostNetwork
      ;
  };

  bridges = import ./bridges.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapBridgeModel
      renderBridgeNetwork
      ;
  };

  containers = import ./containers.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapContainerModel
      renderContainers
      ;
  };
}
