{ lib }:

{
  duplicates =
    xs:
    let
      counts = builtins.listToAttrs (
        map (x: {
          name = x;
          value = lib.length (lib.filter (y: y == x) xs);
        }) xs
      );
    in
    lib.filter (x: (counts.${x} or 0) > 1) (lib.unique xs);
}
