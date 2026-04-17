{
  lib,
  buildControlPlaneOutput ? null,
  writeControlPlaneJSONFromPaths ? null,
}:
let
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
in
{
  controlPlaneOutFromPaths =
    {
      intentPath ? null,
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
}
