{
  lib,
  controlPlaneLib,
}:

let
  importValue = import ../lookup/import-value.nix { inherit lib; };

  buildControlPlaneOutput = import ../lookup/control-plane-output.nix {
    inherit
      lib
      controlPlaneLib
      importValue
      ;
  };

  controlPlaneSource = import ../lookup/control-plane-source-from-paths.nix {
    inherit
      lib
      buildControlPlaneOutput
      ;
  };

  helpers = import ../normalize/helpers.nix { inherit lib; };

  normalizeControlPlane = import ../normalize/control-plane-output.nix {
    inherit
      lib
      helpers
      ;
  };

  normalizeCommunicationContract = import ../normalize/communication-contract.nix {
    inherit lib;
  };

  lookupSiteServiceInputs = import ../lookup/site-service-inputs.nix {
    inherit lib;
  };

  selectDeploymentHost = import ../policy/select-deployment-host.nix {
    inherit lib;
  };

  mapHostModel = import ../map/host-model.nix { inherit lib; };

  mapBridgeModel = import ../map/bridge-model.nix { inherit lib; };

  mapFirewallForwardingRuntimeTargetModel =
    import ../map/firewall-forwarding-runtime-target-model.nix
      { inherit lib; };

  mapFirewallPolicyRuntimeTargetModel = import ../map/firewall-policy-runtime-target-model.nix {
    inherit
      lib
      normalizeCommunicationContract
      lookupSiteServiceInputs
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

  mapKeaRuntimeTargetServiceModel = import ../map/kea-runtime-target-service-model.nix {
    inherit lib;
  };

  mapRadvdRuntimeTargetServiceModel = import ../map/radvd-runtime-target-service-model.nix {
    inherit lib;
  };

  selectContainerRuntimeTargetServiceModels =
    import ../policy/select-container-runtime-target-service-models.nix
      {
        inherit
          lib
          mapKeaRuntimeTargetServiceModel
          mapRadvdRuntimeTargetServiceModel
          ;
      };

  renderHostNetwork = import ../render/networkd-host.nix { inherit lib; };

  renderBridgeNetwork = import ../render/networkd-bridges.nix { inherit lib; };

  renderContainers = import ../render/nixos-containers.nix { inherit lib; };

  renderArtifactEtc = import ../render/nixos-artifacts.nix { inherit lib; };

  renderNftablesRuntimeTarget = import ../render/nftables-runtime-target.nix { inherit lib; };

  renderSimulatedBridges = import ../render/networkd-simulated-bridges.nix { inherit lib; };

  mapContainerRuntimeArtifactContext = import ../map/container-runtime-artifact-context.nix {
    inherit lib;
  };

  mapContainerRuntimeArtifactTree = import ../map/container-runtime-artifact-tree.nix {
    inherit
      lib
      selectFirewallRuntimeTargetModel
      renderNftablesRuntimeTarget
      selectContainerRuntimeTargetServiceModels
      ;
  };

  mapContainerRuntimeArtifactModel = import ../map/container-runtime-artifact-model.nix {
    inherit
      lib
      mapContainerRuntimeArtifactContext
      mapContainerRuntimeArtifactTree
      ;
  };

  mapContainerModel = import ../map/container-model.nix {
    inherit
      lib
      mapContainerRuntimeArtifactModel
      ;
  };

  mapVmContainerSimulatedModel = import ../map/vm-container-simulated-model.nix {
    inherit
      lib
      mapContainerRuntimeArtifactModel
      ;
  };

  mapVmSimulatedHostBridgeModel = import ../map/vm-simulated-host-bridge-model.nix {
    inherit lib;
  };

  mapControlPlaneArtifactTree = import ../map/control-plane-artifact-tree.nix { inherit lib; };

  mapL2ArtifactTree = import ../map/l2-artifact-tree.nix { inherit lib; };

  mapRuntimeTargetArtifactContexts = import ../map/runtime-target-artifact-contexts.nix {
    inherit lib;
  };

  mapAccessServiceArtifactTree = import ../map/access-service-artifact-tree.nix {
    inherit
      lib
      mapRuntimeTargetArtifactContexts
      selectContainerRuntimeTargetServiceModels
      ;
  };

  mapFirewallArtifactTree = import ../map/firewall-artifact-tree.nix {
    inherit
      lib
      mapRuntimeTargetArtifactContexts
      selectFirewallRuntimeTargetModel
      renderNftablesRuntimeTarget
      ;
  };

  rendererApi = import ./renderer.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      ;
  };

  artifactsApi = import ./artifacts.nix {
    inherit
      lib
      controlPlaneSource
      normalizeControlPlane
      mapControlPlaneArtifactTree
      mapL2ArtifactTree
      mapFirewallArtifactTree
      mapAccessServiceArtifactTree
      renderArtifactEtc
      ;
  };

  hostApi = import ./host.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapHostModel
      renderHostNetwork
      ;
    artifacts = artifactsApi;
  };

  bridgesApi = import ./bridges.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapBridgeModel
      renderBridgeNetwork
      ;
    artifacts = artifactsApi;
  };

  containersApi = import ./containers.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapContainerModel
      renderContainers
      ;
    artifacts = artifactsApi;
  };

  vmApi = import ./vm.nix {
    inherit
      lib
      importValue
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapHostModel
      mapBridgeModel
      mapVmContainerSimulatedModel
      mapVmSimulatedHostBridgeModel
      renderHostNetwork
      renderBridgeNetwork
      renderSimulatedBridges
      renderContainers
      ;
    artifacts = artifactsApi;
  };
in
{
  renderer = rendererApi;
  host = hostApi;
  bridges = bridgesApi;
  containers = containersApi;
  artifacts = artifactsApi;
  vm = vmApi;
}
