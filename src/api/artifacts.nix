{
  lib,
  controlPlaneSource,
  normalizeControlPlane,
  mapControlPlaneArtifactTree,
  mapL2ArtifactTree,
  mapFirewallArtifactTree,
  mapAccessServiceArtifactTree,
  renderArtifactEtc,
}:
let
  splitArtifactFilesFromControlPlane =
    {
      controlPlaneOut,
      fileName ? "control-plane-model.json",
      includeFullModel ? true,
    }:
    let
      normalizedModel = normalizeControlPlane controlPlaneOut;

      baseFiles = mapControlPlaneArtifactTree {
        inherit
          normalizedModel
          controlPlaneOut
          includeFullModel
          ;
        fullModelFileName = fileName;
      };

      l2Files = mapL2ArtifactTree {
        inherit normalizedModel;
      };

      firewallFiles = mapFirewallArtifactTree {
        inherit normalizedModel;
      };

      accessServiceFiles = mapAccessServiceArtifactTree {
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
      intentPath ? null,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
    }:
    controlPlaneSource.buildControlPlaneJSONSource {
      controlPlaneOut = controlPlaneSource.controlPlaneOutFromPaths {
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
      intentPath ? null,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
      directory ? "network-artifacts",
      includeFullModel ? true,
    }:
    let
      controlPlaneOut = controlPlaneSource.controlPlaneOutFromPaths {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          fileName
          ;
      };
    in
    renderArtifactEtc {
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
    renderArtifactEtc {
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
      intentPath ? null,
      inventoryPath ? null,
      intent ? null,
      inventory ? null,
      fileName ? "control-plane-model.json",
      directory ? "network-artifacts",
      includeFullModel ? true,
    }:
    let
      controlPlaneOut = controlPlaneSource.controlPlaneOutFromPaths {
        inherit
          intentPath
          inventoryPath
          intent
          inventory
          fileName
          ;
      };
    in
    renderArtifactEtc {
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
