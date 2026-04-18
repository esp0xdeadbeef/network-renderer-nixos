{
  lib,
  cpm ? null,
  uplinks ? { },
  renderedModel,
}:

let
  isa = import ../../alarm/isa18.nix { inherit lib; };

  accessAdvertisementModel =
    if (renderedModel.roleName or null) == "access" then
      import ../../access/lookup/advertisements.nix {
        inherit
          lib
          ;
        containerModel = renderedModel;
      }
    else
      {
        alarms = [ ];
        warnings = [ ];
      };

  firewallAssumptionModel = import ../../firewall/lookup/assumptions.nix {
    inherit
      lib
      cpm
      uplinks
      ;
    runtimeTarget =
      if renderedModel ? runtimeTarget && builtins.isAttrs renderedModel.runtimeTarget then
        renderedModel.runtimeTarget
      else
        { };
    unitName =
      if renderedModel ? unitName && builtins.isString renderedModel.unitName then
        renderedModel.unitName
      else
        null;
    containerName =
      if renderedModel ? containerName && builtins.isString renderedModel.containerName then
        renderedModel.containerName
      else
        null;
    roleName =
      if renderedModel ? roleName && builtins.isString renderedModel.roleName then
        renderedModel.roleName
      else
        null;
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
  };
in
isa.mergeModels [
  accessAdvertisementModel
  firewallAssumptionModel
]
