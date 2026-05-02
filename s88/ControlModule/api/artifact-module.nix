{ debugPayload }:

let
  json = value: builtins.toJSON value;

  renderedHost = debugPayload.renderedHost or { };
in
{
  environment.etc."network-artifacts/compiler.json".text =
    json (debugPayload.compilerOut or { });

  environment.etc."network-artifacts/forwarding.json".text =
    json (debugPayload.forwardingOut or { });

  environment.etc."network-artifacts/control-plane.json".text =
    json (debugPayload.controlPlaneOut or { });

  environment.etc."network-artifacts/intent.json".text =
    json (debugPayload.intent or { });

  environment.etc."network-artifacts/inventory.json".text =
    json (debugPayload.globalInventory or { });

  environment.etc."network-artifacts/rendered-host.json".text =
    json renderedHost;

  environment.etc."network-artifacts/debug-bundle.json".text =
    json debugPayload;

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    json {
      renderer = "network-renderer-nixos";
      hostName = debugPayload.hostName or null;
      system = debugPayload.system or null;
      intentPath = debugPayload.intentPath or null;
      inventoryPath = debugPayload.inventoryPath or null;
      selectedUnits = renderedHost.selectedUnits or [ ];
      selectedRoleNames = renderedHost.selectedRoleNames or [ ];
      containers = builtins.attrNames (renderedHost.containers or { });
      artifactBundle = "/etc/network-artifacts/debug-bundle.json";
    };
}
