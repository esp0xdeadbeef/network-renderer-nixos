{
  selectors,
  builders,
  renderDryConfig,
}:

let
  buildAndRenderFromPaths =
    {
      intentPath,
      inventoryPath,
      exampleDir ? null,
      debug ? false,
    }:
    let
      inventory = selectors.importMaybeFunction (builtins.toPath inventoryPath);

      compiler = builders.buildCompilerFromPaths {
        inherit intentPath;
      };

      forwarding = builders.buildForwarding {
        compilerOut = compiler;
      };

      controlPlane = builders.buildControlPlane {
        forwardingOut = forwarding;
        inherit inventory;
      };

      rendered = renderDryConfig {
        cpm = controlPlane;
        inherit inventory exampleDir debug;
      };
    in
    if rendered == null then
      throw ''
        s88/Unit/api/dry-render-build.nix: buildAndRenderFromPaths produced null render output

        intentPath: ${intentPath}
        inventoryPath: ${inventoryPath}
      ''
    else
      {
        inherit compiler forwarding;
        controlPlane = controlPlane;
        render = rendered;
      };
in
{
  inherit buildAndRenderFromPaths;
}
