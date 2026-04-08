{ lib }:
let
  getAttrPathOr =
    path: default: set:
    if path == [ ] then
      set
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if !(builtins.isAttrs set) || !(builtins.hasAttr key set) then
        default
      else
        getAttrPathOr rest default (builtins.getAttr key set);

  pickFirstAttrPath =
    paths: default: set:
    if paths == [ ] then
      default
    else
      let
        path = builtins.head paths;
        rest = builtins.tail paths;
        value = getAttrPathOr path null set;
      in
      if value == null then pickFirstAttrPath rest default set else value;
in
{
  inherit
    getAttrPathOr
    pickFirstAttrPath
    ;

  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";
}
