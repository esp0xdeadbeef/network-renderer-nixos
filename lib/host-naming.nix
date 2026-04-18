{ lib }:

let
  maxLen = 15;

  hash = name: builtins.substring 0 6 (builtins.hashString "sha256" name);

  shorten =
    name:
    if builtins.stringLength name <= maxLen then
      name
    else
      let
        prefixLen = maxLen - 7;
        prefix = builtins.substring 0 prefixLen name;
      in
      "${prefix}-${hash name}";

  ensureUnique =
    names:
    let
      shortened = map (n: {
        original = n;
        rendered = shorten n;
      }) names;

      grouped = builtins.foldl' (
        acc: entry:
        let
          key = entry.rendered;
        in
        acc
        // {
          ${key} = (acc.${key} or [ ]) ++ [ entry.original ];
        }
      ) { } shortened;

      collisions = lib.filterAttrs (_: v: builtins.length v > 1) grouped;
    in
    if collisions != { } then
      throw ''
        host-naming: collision detected after shortening

        ${builtins.toJSON collisions}
      ''
    else
      builtins.listToAttrs (
        map (entry: {
          name = entry.original;
          value = entry.rendered;
        }) shortened
      );
in
{
  inherit shorten ensureUnique;
}
