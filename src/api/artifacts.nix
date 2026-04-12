{
  lib,
  buildControlPlaneOutput ? null,
  normalizeControlPlane ? null,
  mapControlPlaneArtifactTree ? null,
  mapL2ArtifactTree ? null,
  mapRuntimeTargetArtifactContexts ? null,
  selectFirewallRuntimeTargetModel ? null,
  mapAccessServiceArtifactTree ? null,
  renderArtifactEtc ? null,
  renderNftablesRuntimeTarget ? null,
  writeControlPlaneJSONFromPaths ? null,
}:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  normalizeControlPlaneResolved =
    if normalizeControlPlane != null then
      normalizeControlPlane
    else
      let
        helpers = import ../normalize/helpers.nix { inherit lib; };
      in
      import ../normalize/control-plane-output.nix {
        inherit
          lib
          helpers
          ;
      };

  mapControlPlaneArtifactTreeResolved =
    if mapControlPlaneArtifactTree != null then
      mapControlPlaneArtifactTree
    else
      import ../map/control-plane-artifact-tree.nix { inherit lib; };

  mapL2ArtifactTreeResolved =
    if mapL2ArtifactTree != null then
      mapL2ArtifactTree
    else
      import ../map/l2-artifact-tree.nix { inherit lib; };

  mapRuntimeTargetArtifactContextsResolved =
    if mapRuntimeTargetArtifactContexts != null then
      mapRuntimeTargetArtifactContexts
    else
      import ../map/runtime-target-artifact-contexts.nix { inherit lib; };

  selectFirewallRuntimeTargetModelResolved =
    if selectFirewallRuntimeTargetModel != null then
      selectFirewallRuntimeTargetModel
    else
      let
        normalizeCommunicationContract = import ../normalize/communication-contract.nix { inherit lib; };

        lookupSiteServiceInputs = import ../lookup/site-service-inputs.nix { inherit lib; };

        mapFirewallForwardingRuntimeTargetModel =
          import ../map/firewall-forwarding-runtime-target-model.nix
            { inherit lib; };

        mapFirewallPolicyRuntimeTargetModel = import ../map/firewall-policy-runtime-target-model.nix {
          inherit
            lib
            normalizeCommunicationContract
            ;
        };
      in
      import ../policy/select-firewall-runtime-target-model.nix {
        inherit
          lib
          lookupSiteServiceInputs
          mapFirewallForwardingRuntimeTargetModel
          mapFirewallPolicyRuntimeTargetModel
          ;
      };

  mapAccessServiceArtifactTreeResolved =
    if mapAccessServiceArtifactTree != null then
      mapAccessServiceArtifactTree
    else
      let
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
      in
      import ../map/access-service-artifact-tree.nix {
        inherit
          lib
          selectContainerRuntimeTargetServiceModels
          ;
        mapRuntimeTargetArtifactContexts = mapRuntimeTargetArtifactContextsResolved;
      };

  renderArtifactEtcResolved =
    if renderArtifactEtc != null then
      renderArtifactEtc
    else
      import ../render/nixos-artifacts.nix { inherit lib; };

  renderNftablesRuntimeTargetResolved =
    if renderNftablesRuntimeTarget != null then
      renderNftablesRuntimeTarget
    else
      import ../render/nftables-runtime-target.nix { inherit lib; };

  stripRendererInputs =
    controlPlaneOut:
    builtins.removeAttrs controlPlaneOut [
      "fabricInputs"
      "globalInventory"
    ];

  requireSplitInputBuilder =
    if buildControlPlaneOutput != null then
      true
    else
      throw "network-renderer-nixos: buildControlPlaneOutput is required when rendering split artifacts from inline values";

  requireLegacyInputBuilder =
    if writeControlPlaneJSONFromPaths != null then
      true
    else
      throw "network-renderer-nixos: writeControlPlaneJSONFromPaths is required when rendering split artifacts from paths";

  controlPlaneOutFromInlineOrPaths =
    {
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
    }:
    builtins.seq requireSplitInputBuilder (buildControlPlaneOutput {
      inherit
        intentPath
        inventoryPath
        intent
        inventory
        ;
    });

  controlPlaneOutFromLegacyPaths =
    {
      intentPath,
      inventoryPath ? null,
      fileName ? "control-plane-model.json",
    }:
    let
      source = builtins.seq requireLegacyInputBuilder (writeControlPlaneJSONFromPaths {
        inputPath = intentPath;
        inherit inventoryPath;
        name = fileName;
      });
    in
    builtins.fromJSON (builtins.readFile source);

  controlPlaneOutFromPaths =
    {
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
    }:
    if buildControlPlaneOutput != null then
      controlPlaneOutFromInlineOrPaths {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          ;
      }
    else if intent != null || inventory != null then
      throw "network-renderer-nixos: inline intent/inventory requires buildControlPlaneOutput"
    else
      controlPlaneOutFromLegacyPaths {
        inherit
          intentPath
          inventoryPath
          fileName
          ;
      };

  buildControlPlaneJSONSource =
    {
      controlPlaneOut,
      fileName ? "control-plane-model.json",
    }:
    builtins.toFile fileName (builtins.toJSON (stripRendererInputs controlPlaneOut));

  renderFirewallArtifactFiles =
    {
      normalizedModel,
    }:
    let
      runtimeTargetContexts = mapRuntimeTargetArtifactContextsResolved {
        inherit normalizedModel;
      };

      firewallContextNames = lib.filter (
        contextName:
        let
          context = runtimeTargetContexts.${contextName};
          runtimeTarget =
            if context ? runtimeTarget && builtins.isAttrs context.runtimeTarget then
              context.runtimeTarget
            else
              null;
        in
        runtimeTarget != null
        && runtimeTarget ? forwardingIntent
        && builtins.isAttrs runtimeTarget.forwardingIntent
      ) (sortedAttrNames runtimeTargetContexts);

      fileEntries = lib.concatMap (
        contextName:
        let
          context = runtimeTargetContexts.${contextName};
          firewallModel = selectFirewallRuntimeTargetModelResolved {
            inherit normalizedModel;
            artifactContext = context;
          };
          renderedRules = renderNftablesRuntimeTargetResolved firewallModel;
        in
        [
          {
            name = "${context.artifactPathPrefix}/firewall/nftables.nft";
            value = {
              format = "text";
              value = renderedRules;
            };
          }
        ]
      ) firewallContextNames;

      filePaths = map (entry: entry.name) fileEntries;

      _uniquePaths =
        if builtins.length filePaths == builtins.length (lib.unique filePaths) then
          true
        else
          throw "network-renderer-nixos: firewall artifact rendering produced duplicate paths";
    in
    builtins.seq _uniquePaths (builtins.listToAttrs fileEntries);

  splitArtifactFilesFromControlPlane =
    {
      controlPlaneOut,
      fileName ? "control-plane-model.json",
      includeFullModel ? true,
    }:
    let
      normalizedModel = normalizeControlPlaneResolved controlPlaneOut;

      baseFiles = mapControlPlaneArtifactTreeResolved {
        inherit
          normalizedModel
          controlPlaneOut
          includeFullModel
          ;
        fullModelFileName = fileName;
      };

      l2Files = mapL2ArtifactTreeResolved {
        inherit normalizedModel;
      };

      firewallFiles = renderFirewallArtifactFiles {
        inherit normalizedModel;
      };

      accessServiceFiles = mapAccessServiceArtifactTreeResolved {
        inherit normalizedModel;
      };

      mergedFiles = baseFiles // l2Files // firewallFiles // accessServiceFiles;
      mergedPaths = builtins.attrNames mergedFiles;

      _uniqueMergedPaths =
        if builtins.length mergedPaths == builtins.length (lib.unique mergedPaths) then
          true
        else
          throw "network-renderer-nixos: artifact rendering produced duplicate output paths";
    in
    builtins.seq _uniqueMergedPaths mergedFiles;
in
{
  controlPlaneJSONFromPaths =
    {
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
    }:
    buildControlPlaneJSONSource {
      controlPlaneOut = controlPlaneOutFromPaths {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          fileName
          ;
      };
      inherit fileName;
    };

  controlPlaneFromPaths =
    {
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
      directory ? "network-artifacts",
      includeFullModel ? true,
    }:
    let
      controlPlaneOut = controlPlaneOutFromPaths {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          fileName
          ;
      };
    in
    renderArtifactEtcResolved {
      inherit directory;
      files = splitArtifactFilesFromControlPlane {
        inherit
          controlPlaneOut
          fileName
          includeFullModel
          ;
      };
    };

  controlPlaneSplitFromControlPlane =
    {
      controlPlaneOut,
      fileName ? "control-plane-model.json",
      directory ? "network-artifacts",
      includeFullModel ? true,
    }:
    renderArtifactEtcResolved {
      inherit directory;
      files = splitArtifactFilesFromControlPlane {
        inherit
          controlPlaneOut
          fileName
          includeFullModel
          ;
      };
    };

  controlPlaneSplitFromPaths =
    {
      intentPath,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
      directory ? "network-artifacts",
      includeFullModel ? true,
    }:
    let
      controlPlaneOut = controlPlaneOutFromPaths {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          fileName
          ;
      };
    in
    renderArtifactEtcResolved {
      inherit directory;
      files = splitArtifactFilesFromControlPlane {
        inherit
          controlPlaneOut
          fileName
          includeFullModel
          ;
      };
    };
}
