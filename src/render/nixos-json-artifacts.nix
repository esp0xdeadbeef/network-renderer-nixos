{ lib }:
{
  directory ? "network-artifacts",
  jsonFiles,
}:
let
  files =
    if builtins.isAttrs jsonFiles then
      jsonFiles
    else
      throw "network-renderer-nixos: expected jsonFiles to be an attribute set";

  fileNames = lib.sort builtins.lessThan (builtins.attrNames files);

  mkSource =
    fileName: value:
    builtins.toFile "network-renderer-nixos-${builtins.hashString "sha256" fileName}.json" (
      builtins.toJSON value
    );
in
{
  environment.etc = builtins.listToAttrs (
    map (fileName: {
      name = "${directory}/${fileName}";
      value = {
        source = mkSource fileName files.${fileName};
      };
    }) fileNames
  );
}
