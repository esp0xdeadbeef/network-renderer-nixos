{
  lib,
  cpm ? null,
  inventory ? { },
  uplinks ? { },
  renderedModel,
}:

let
  firewall = import ../../firewall/default.nix { inherit lib; };

  mkFirewallArg =
    nftRuleset:
    if builtins.isString nftRuleset && nftRuleset != "" then
      {
        enable = true;
        ruleset = nftRuleset;
      }
    else
      {
        enable = false;
        ruleset = null;
      };
in
if cpm == null then
  if renderedModel ? firewall && builtins.isAttrs renderedModel.firewall then
    renderedModel.firewall
  else
    {
      enable = false;
      ruleset = null;
    }
else
  mkFirewallArg (firewall {
    inherit cpm inventory uplinks;
    unitKey = if renderedModel ? unitKey then renderedModel.unitKey else null;
    unitName = if renderedModel ? unitName then renderedModel.unitName else null;
    roleName = if renderedModel ? roleName then renderedModel.roleName else null;
    runtimeTarget =
      if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
        renderedModel.runtimeTarget
      else
        { };
    interfaces =
      if renderedModel ? interfaces && builtins.isAttrs renderedModel.interfaces then
        renderedModel.interfaces
      else
        { };
    wanIfs =
      if renderedModel ? wanInterfaceNames && builtins.isList renderedModel.wanInterfaceNames then
        renderedModel.wanInterfaceNames
      else
        [ ];
    lanIfs =
      if renderedModel ? lanInterfaceNames && builtins.isList renderedModel.lanInterfaceNames then
        renderedModel.lanInterfaceNames
      else
        [ ];
  })
