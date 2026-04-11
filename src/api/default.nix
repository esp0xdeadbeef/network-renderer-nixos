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

  normalizeCommunicationContract = import ../normalize/communication-contract.nix { inherit lib; };

  lookupSiteServiceInputs = import ../lookup/site-service-inputs.nix { inherit lib; };

  selectDeploymentHost = import ../policy/select-deployment-host.nix { inherit lib; };
  selectRenderHost = import ../policy/select-render-host.nix { inherit lib; };

  mapHostModel = import ../map/host-model.nix { inherit lib; };
  mapBridgeModel = import ../map/bridge-model.nix { inherit lib; };
  mapContainerModel = import ../map/container-model.nix { inherit lib; };
  mapControlPlaneArtifactTree = import ../map/control-plane-artifact-tree.nix { inherit lib; };
  mapRuntimeTargetArtifactContexts = import ../map/runtime-target-artifact-contexts.nix {
    inherit lib;
  };
  mapFirewallForwardingRuntimeTargetModel =
    import ../map/firewall-forwarding-runtime-target-model.nix
      { inherit lib; };
  mapFirewallPolicyRuntimeTargetModel = import ../map/firewall-policy-runtime-target-model.nix {
    inherit
      lib
      normalizeCommunicationContract
      ;
  };

  selectFirewallRuntimeTargetModel = import ../policy/select-firewall-runtime-target-model.nix {
    inherit
      lib
      lookupSiteServiceInputs
      mapFirewallForwardingRuntimeTargetModel
      mapFirewallPolicyRuntimeTargetModel
      ;
  };

  renderHostNetwork = import ../render/networkd-host.nix { inherit lib; };
  renderBridgeNetwork = import ../render/networkd-bridges.nix { inherit lib; };
  renderContainers = import ../render/nixos-containers.nix { inherit lib; };
  renderArtifactEtc = import ../render/nixos-artifacts.nix { inherit lib; };
  renderNftablesRuntimeTarget = import ../render/nftables-runtime-target.nix { inherit lib; };
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

  artifacts = import ./artifacts.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      mapControlPlaneArtifactTree
      mapRuntimeTargetArtifactContexts
      selectFirewallRuntimeTargetModel
      renderArtifactEtc
      renderNftablesRuntimeTarget
      ;
  };
}
