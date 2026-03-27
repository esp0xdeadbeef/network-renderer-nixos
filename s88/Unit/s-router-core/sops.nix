{ lib, globalInventory, ... }:

let
  secretSpecs =
    if globalInventory ? secrets && builtins.isAttrs globalInventory.secrets then
      globalInventory.secrets
    else
      { };

  mkSecret =
    name:
    let
      spec = secretSpecs.${name};
    in
    {
      name = name;
      value = {
        owner =
          if spec ? owner && builtins.isString spec.owner then
            spec.owner
          else
            "root";

        mode =
          if spec ? mode && builtins.isString spec.mode then
            spec.mode
          else
            "0400";
      };
    };
in
{
  sops.secrets = builtins.listToAttrs (map mkSecret (builtins.attrNames secretSpecs));
}
