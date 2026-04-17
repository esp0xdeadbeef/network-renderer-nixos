{
  lib,
  controlPlaneLib ? null,
}:

let
  resolveControlPlaneBuilder =
    libValue:
    if libValue == null then
      null
    else if libValue ? buildControlPlaneOutput then
      libValue.buildControlPlaneOutput
    else if libValue ? compileAndBuildFromPaths then
      args:
      libValue.compileAndBuildFromPaths {
        inputPath = args.intentPath;
        inventoryPath = args.inventoryPath or null;
      }
    else if libValue ? writeCompileAndBuildJSON then
      args:
      builtins.fromJSON (
        builtins.readFile (
          libValue.writeCompileAndBuildJSON {
            inputPath = args.intentPath;
            inventoryPath = args.inventoryPath or null;
            name = "control-plane-model.json";
          }
        )
      )
    else if libValue ? build then
      args:
      libValue.build {
        input = if args ? intent && args.intent != null then args.intent else import args.intentPath;
        inventory =
          if args ? inventory && args.inventory != null then
            args.inventory
          else if args ? inventoryPath && args.inventoryPath != null then
            import args.inventoryPath
          else
            { };
      }
    else if libValue ? compileAndBuild then
      args:
      libValue.compileAndBuild {
        input = if args ? intent && args.intent != null then args.intent else import args.intentPath;
        inventory =
          if args ? inventory && args.inventory != null then
            args.inventory
          else if args ? inventoryPath && args.inventoryPath != null then
            import args.inventoryPath
          else
            { };
      }
    else
      null;

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

  resolvedControlPlaneBuilder = resolveControlPlaneBuilder controlPlaneLib;

  buildControlPlaneOutput =
    if resolvedControlPlaneBuilder != null then
      resolvedControlPlaneBuilder
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

  lookupSiteServiceInputsRaw = import ../lookup/site-service-inputs.nix {
    inherit lib;
  };

  lookupSiteServiceInputs =
    args:
    if args ? artifactContext then
      let
        context = args.artifactContext;
      in
      lookupSiteServiceInputsRaw {
        inherit (args) normalizedModel;
        enterpriseName = context.enterpriseName;
        siteName = context.siteName;
      }
    else
      lookupSiteServiceInputsRaw args;

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
  mapAccessServiceArtifactTree = import ../map/access-service-artifact-tree.nix {
    inherit lib;
  };

  renderHost = import ../render/networkd-host.nix { inherit lib; };
  renderBridges = import ../render/networkd-bridges.nix { inherit lib; };
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
in
rec {
  renderer = {
    buildControlPlaneFromPaths =
      {
        intentPath,
        inventoryPath,
      }:
      buildControlPlaneOutput {
        inherit
          intentPath
          inventoryPath
          ;
      };

    buildHostFromPaths =
      {
        intentPath,
        inventoryPath,
        selector,
        file ? null,
      }:
      let
        builtControlPlaneOut = buildControlPlaneOutput {
          inherit
            intentPath
            inventoryPath
            ;
        };

        normalizedModel = normalizeControlPlane builtControlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          boxName = selector;
        };
      in
      {
        inherit normalizedModel;
        hostContext = {
          boxName = selector;
          hostName = selector;
          deploymentHostName = deploymentHost.name;
          deploymentHost = deploymentHost.definition;
          file = file;
        };
        fabricInputs = {
          inherit
            intentPath
            inventoryPath
            selector
            file
            ;
        };
        compilerOut = builtControlPlaneOut.compilerOut or { };
        forwardingOut = builtControlPlaneOut.forwardingOut or { };
        controlPlaneOut = builtControlPlaneOut;
        globalInventory = builtControlPlaneOut.globalInventory or { };
      };
  };

  host = {
    build =
      {
        enterpriseName,
        siteName,
        boxName,
        intentPath,
        inventoryPath,
      }:
      let
        builtControlPlaneOut = buildControlPlaneOutput {
          inherit
            intentPath
            inventoryPath
            ;
        };

        normalizedModel = normalizeControlPlane builtControlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          inherit boxName;
        };

        hostModel = mapHostModel {
          boxName = deploymentHost.name;
          deploymentHostDef = deploymentHost.definition;
        };
      in
      renderHost hostModel;

    buildFromControlPlane =
      {
        controlPlaneOut,
        boxName,
      }:
      let
        normalizedModel = normalizeControlPlane controlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          inherit boxName;
        };

        hostModel = mapHostModel {
          boxName = deploymentHost.name;
          deploymentHostDef = deploymentHost.definition;
        };
      in
      renderHost hostModel;
  };

  bridges = {
    build =
      {
        enterpriseName,
        siteName,
        boxName,
        intentPath,
        inventoryPath,
      }:
      let
        builtControlPlaneOut = buildControlPlaneOutput {
          inherit
            intentPath
            inventoryPath
            ;
        };

        normalizedModel = normalizeControlPlane builtControlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          inherit boxName;
        };

        bridgeModel = mapBridgeModel {
          boxName = deploymentHost.name;
          deploymentHostDef = deploymentHost.definition;
        };
      in
      renderBridges bridgeModel;

    buildFromControlPlane =
      {
        controlPlaneOut,
        boxName,
      }:
      let
        normalizedModel = normalizeControlPlane controlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          inherit boxName;
        };

        bridgeModel = mapBridgeModel {
          boxName = deploymentHost.name;
          deploymentHostDef = deploymentHost.definition;
        };
      in
      renderBridges bridgeModel;
  };

  containers = {
    buildForBox =
      {
        enterpriseName,
        siteName,
        boxName,
        intentPath,
        inventoryPath,
        disabled ? { },
        defaults ? { },
      }:
      let
        builtControlPlaneOut = buildControlPlaneOutput {
          inherit
            intentPath
            inventoryPath
            ;
        };

        normalizedModel = normalizeControlPlane builtControlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          inherit boxName;
        };

        containerModel = mapContainerModel {
          model = normalizedModel;
          boxName = deploymentHost.name;
          deploymentHostDef = deploymentHost.definition;
          inherit
            disabled
            defaults
            ;
        };
      in
      renderContainers containerModel;

    buildFromControlPlane =
      {
        controlPlaneOut,
        boxName,
        disabled ? { },
        defaults ? { },
      }:
      let
        normalizedModel = normalizeControlPlane controlPlaneOut;

        deploymentHost = selectDeploymentHost {
          model = normalizedModel;
          inherit boxName;
        };

        containerModel = mapContainerModel {
          model = normalizedModel;
          boxName = deploymentHost.name;
          deploymentHostDef = deploymentHost.definition;
          inherit
            disabled
            defaults
            ;
        };
      in
      renderContainers containerModel;
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
}
