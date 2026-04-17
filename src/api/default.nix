{
  lib,
  controlPlaneLib ? null,
}:

let
  fallbackBuildControlPlaneOutputPath =
    let
      candidates = [
        ../build-control-plane-output.nix
        ./build-control-plane-output.nix
        ../control-plane/build-control-plane-output.nix
        ../compile/build-control-plane-output.nix
        ../compiler/build-control-plane-output.nix
        ../orchestrate/build-control-plane-output.nix
        ../orchestration/build-control-plane-output.nix
        ../pipeline/build-control-plane-output.nix
      ];

      existing = lib.filter builtins.pathExists candidates;
    in
    if existing != [ ] then builtins.head existing else null;

  importValue = import ../lookup/import-value.nix { inherit lib; };

  attachRendererInputs =
    {
      result,
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
    }:
    let
      resolvedIntent = if intent != null then intent else importValue intentPath;

      resolvedInventory =
        if inventory != null then
          inventory
        else if inventoryPath == null then
          { }
        else
          importValue inventoryPath;

      normalizedResult = if builtins.isAttrs result then result else { control_plane_model = result; };
    in
    normalizedResult
    // {
      fabricInputs = resolvedIntent;
      globalInventory = resolvedInventory;
      inventory = resolvedInventory;
    };

  buildControlPlaneOutputFromLib =
    if controlPlaneLib == null then
      null
    else if controlPlaneLib ? buildControlPlaneOutput then
      args: attachRendererInputs (args // { result = controlPlaneLib.buildControlPlaneOutput args; })
    else if controlPlaneLib ? compileAndBuildFromPaths then
      {
        intentPath,
        inventoryPath ? null,
        intent ? null,
        inventory ? null,
      }:
      if intent != null || inventory != null then
        let
          resolvedIntent = if intent != null then intent else importValue intentPath;
          resolvedInventory =
            if inventory != null then
              inventory
            else if inventoryPath == null then
              { }
            else
              importValue inventoryPath;

          result =
            if controlPlaneLib ? build then
              controlPlaneLib.build {
                input = resolvedIntent;
                inventory = resolvedInventory;
              }
            else if controlPlaneLib ? compileAndBuild then
              controlPlaneLib.compileAndBuild {
                input = resolvedIntent;
                inventory = resolvedInventory;
              }
            else if controlPlaneLib ? getCPM then
              {
                control_plane_model = controlPlaneLib.getCPM {
                  input = resolvedIntent;
                  inventory = resolvedInventory;
                };
              }
            else if controlPlaneLib ? get_CPM then
              {
                control_plane_model = controlPlaneLib.get_CPM {
                  input = resolvedIntent;
                  inventory = resolvedInventory;
                };
              }
            else
              throw ''
                network-renderer-nixos: src/api/default.nix received inline intent/inventory, but controlPlaneLib does not expose build/compileAndBuild/getCPM/get_CPM
              '';
        in
        attachRendererInputs {
          inherit
            result
            intentPath
            inventoryPath
            intent
            inventory
            ;
        }
      else
        attachRendererInputs {
          result = controlPlaneLib.compileAndBuildFromPaths {
            inputPath = intentPath;
            inherit inventoryPath;
          };
          inherit
            intentPath
            inventoryPath
            intent
            inventory
            ;
        }
    else if controlPlaneLib ? build then
      {
        intentPath,
        inventoryPath ? null,
        intent ? null,
        inventory ? null,
      }:
      let
        resolvedIntent = if intent != null then intent else importValue intentPath;
        resolvedInventory =
          if inventory != null then
            inventory
          else if inventoryPath == null then
            { }
          else
            importValue inventoryPath;
      in
      attachRendererInputs {
        result = controlPlaneLib.build {
          input = resolvedIntent;
          inventory = resolvedInventory;
        };
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      }
    else if controlPlaneLib ? compileAndBuild then
      {
        intentPath,
        inventoryPath ? null,
        intent ? null,
        inventory ? null,
      }:
      let
        resolvedIntent = if intent != null then intent else importValue intentPath;
        resolvedInventory =
          if inventory != null then
            inventory
          else if inventoryPath == null then
            { }
          else
            importValue inventoryPath;
      in
      attachRendererInputs {
        result = controlPlaneLib.compileAndBuild {
          input = resolvedIntent;
          inventory = resolvedInventory;
        };
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      }
    else if controlPlaneLib ? getCPM then
      {
        intentPath,
        inventoryPath ? null,
        intent ? null,
        inventory ? null,
      }:
      let
        resolvedIntent = if intent != null then intent else importValue intentPath;
        resolvedInventory =
          if inventory != null then
            inventory
          else if inventoryPath == null then
            { }
          else
            importValue inventoryPath;
      in
      attachRendererInputs {
        result = {
          control_plane_model = controlPlaneLib.getCPM {
            input = resolvedIntent;
            inventory = resolvedInventory;
          };
        };
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      }
    else if controlPlaneLib ? get_CPM then
      {
        intentPath,
        inventoryPath ? null,
        intent ? null,
        inventory ? null,
      }:
      let
        resolvedIntent = if intent != null then intent else importValue intentPath;
        resolvedInventory =
          if inventory != null then
            inventory
          else if inventoryPath == null then
            { }
          else
            importValue inventoryPath;
      in
      attachRendererInputs {
        result = {
          control_plane_model = controlPlaneLib.get_CPM {
            input = resolvedIntent;
            inventory = resolvedInventory;
          };
        };
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      }
    else
      null;

  buildControlPlaneOutput =
    if buildControlPlaneOutputFromLib != null then
      buildControlPlaneOutputFromLib
    else if fallbackBuildControlPlaneOutputPath != null then
      import fallbackBuildControlPlaneOutputPath { inherit lib; }
    else
      throw ''
        network-renderer-nixos: src/api/default.nix could not resolve build-control-plane-output.nix
        Tried:
        - src/build-control-plane-output.nix
        - src/api/build-control-plane-output.nix
        - src/control-plane/build-control-plane-output.nix
        - src/compile/build-control-plane-output.nix
        - src/compiler/build-control-plane-output.nix
        - src/orchestrate/build-control-plane-output.nix
        - src/orchestration/build-control-plane-output.nix
        - src/pipeline/build-control-plane-output.nix
        Provide controlPlaneLib.buildControlPlaneOutput when importing src/api/default.nix if your tree keeps the builder elsewhere.
      '';

  helpers = import ../normalize/helpers.nix { inherit lib; };

  normalizeCommunicationContract = import ../normalize/communication-contract.nix {
    inherit lib;
  };

  normalizeControlPlane = import ../normalize/control-plane-output.nix {
    inherit
      lib
      helpers
      ;
  };

  selectDeploymentHost = import ../policy/select-deployment-host.nix { inherit lib; };

  lookupSiteServiceInputs = import ../lookup/site-service-inputs.nix {
    inherit lib;
  };

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

  mapHostModel = import ../map/host-model.nix { inherit lib; };
  mapBridgeModel = import ../map/bridge-model.nix { inherit lib; };
  mapControlPlaneArtifactTree = import ../map/control-plane-artifact-tree.nix { inherit lib; };
  mapL2ArtifactTree = import ../map/l2-artifact-tree.nix { inherit lib; };
  mapRuntimeTargetArtifactContexts = import ../map/runtime-target-artifact-contexts.nix {
    inherit lib;
  };

  renderHostNetwork = import ../render/networkd-host.nix { inherit lib; };
  renderBridgeNetwork = import ../render/networkd-bridges.nix { inherit lib; };
  renderContainers = import ../render/nixos-containers.nix { inherit lib; };
  renderArtifactEtc = import ../render/nixos-artifacts.nix { inherit lib; };
  renderNftablesRuntimeTarget = import ../render/nftables-runtime-target.nix { inherit lib; };

  mapContainerRuntimeArtifactModel = import ../map/container-runtime-artifact-model.nix {
    inherit
      lib
      selectFirewallRuntimeTargetModel
      renderNftablesRuntimeTarget
      selectContainerRuntimeTargetServiceModels
      ;
  };

  mapContainerModel = import ../map/container-model.nix {
    inherit
      lib
      mapContainerRuntimeArtifactModel
      ;
  };

  mapAccessServiceArtifactTree = import ../map/access-service-artifact-tree.nix {
    inherit
      lib
      mapRuntimeTargetArtifactContexts
      selectContainerRuntimeTargetServiceModels
      ;
  };

  artifacts = import ./artifacts.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      mapControlPlaneArtifactTree
      mapL2ArtifactTree
      mapRuntimeTargetArtifactContexts
      selectFirewallRuntimeTargetModel
      mapAccessServiceArtifactTree
      renderArtifactEtc
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

  hostApi = import ./host.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapHostModel
      ;
    renderHostNetwork = renderHostNetwork;
  };

  bridgesApi = import ./bridges.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapBridgeModel
      ;
    renderBridgeNetwork = renderBridgeNetwork;
  };

  containersApi = import ./containers.nix {
    inherit
      lib
      buildControlPlaneOutput
      normalizeControlPlane
      selectDeploymentHost
      mapContainerModel
      renderContainers
      artifacts
      ;
  };
in
{
  renderer = rendererApi;
  host = hostApi;
  bridges = bridgesApi;
  containers = containersApi;
  inherit artifacts;
}
