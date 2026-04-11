{ lib }:
{
  directory ? "network-artifacts",
  files,
}:
let
  fileEntries =
    if builtins.isAttrs files then
      files
    else
      throw "network-renderer-nixos: expected files to be an attribute set";

  fileNames = lib.sort builtins.lessThan (builtins.attrNames fileEntries);

  fileExtension =
    fileName:
    let
      match = builtins.match ".*(\\.[A-Za-z0-9_-]+)$" fileName;
    in
    if match == null then "" else builtins.head match;

  mkSource =
    fileName: content:
    builtins.toFile "network-renderer-nixos-${builtins.hashString "sha256" fileName}${fileExtension fileName}" content;

  renderFile =
    fileName:
    let
      entry = fileEntries.${fileName};
    in
    if builtins.isAttrs entry && entry ? source then
      entry
    else if builtins.isAttrs entry && entry ? format && entry ? value then
      if entry.format == "json" then
        {
          source = mkSource fileName (builtins.toJSON entry.value);
        }
      else if entry.format == "text" then
        if builtins.isString entry.value then
          {
            source = mkSource fileName entry.value;
          }
        else
          throw "network-renderer-nixos: expected text artifact '${fileName}' to contain a string"
      else
        throw "network-renderer-nixos: unsupported artifact format '${entry.format}' for '${fileName}'"
    else
      {
        source = mkSource fileName (builtins.toJSON entry);
      };
in
{
  environment.etc = builtins.listToAttrs (
    map (fileName: {
      name = "${directory}/${fileName}";
      value = renderFile fileName;
    }) fileNames
  );
}
