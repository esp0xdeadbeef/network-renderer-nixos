{ lib }:

let
  runtimeContext = import ../../lookup/runtime-context.nix { inherit lib; };

  attrPathOrNull =
    attrs: path:
    if path == [ ] then
      attrs
    else if !builtins.isAttrs attrs then
      null
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if builtins.hasAttr key attrs then attrPathOrNull attrs.${key} rest else null;

  lastStringSegment =
    separator: value:
    let
      parts = lib.splitString separator value;
      count = builtins.length parts;
    in
    if count == 0 then null else builtins.elemAt parts (count - 1);

  forwardingModelFromCpm =
    cpm:
    if cpm ? forwardingModel && builtins.isAttrs cpm.forwardingModel then
      cpm.forwardingModel
    else if
      cpm ? control_plane_model
      && builtins.isAttrs cpm.control_plane_model
      && cpm.control_plane_model ? forwardingModel
      && builtins.isAttrs cpm.control_plane_model.forwardingModel
    then
      cpm.control_plane_model.forwardingModel
    else
      { };

  forwardingSiteForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode =
        if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
          runtimeTarget.logicalNode
        else
          { };

      enterprise =
        if logicalNode ? enterprise && builtins.isString logicalNode.enterprise then
          logicalNode.enterprise
        else
          null;

      site = if logicalNode ? site && builtins.isString logicalNode.site then logicalNode.site else null;

      candidate =
        if enterprise != null && site != null then
          attrPathOrNull (forwardingModelFromCpm cpm) [
            "enterprise"
            enterprise
            "site"
            site
          ]
        else
          null;
    in
    if builtins.isAttrs candidate then candidate else { };

  forwardingNodeInterfacesForUnit =
    {
      cpm,
      unitName,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      runtimeTarget = runtimeContext.runtimeTargetForUnit {
        inherit cpm unitName file;
      };

      logicalNode =
        if runtimeTarget ? logicalNode && builtins.isAttrs runtimeTarget.logicalNode then
          runtimeTarget.logicalNode
        else
          { };

      nodeName =
        if logicalNode ? name && builtins.isString logicalNode.name then logicalNode.name else unitName;

      site = forwardingSiteForUnit {
        inherit cpm unitName file;
      };

      nodes = if site ? nodes && builtins.isAttrs site.nodes then site.nodes else { };

      node =
        if builtins.hasAttr nodeName nodes && builtins.isAttrs nodes.${nodeName} then
          nodes.${nodeName}
        else
          { };
    in
    if node ? interfaces && builtins.isAttrs node.interfaces then node.interfaces else { };

  semanticInterfaceForUnit =
    {
      cpm,
      unitName,
      ifName,
      iface,
      file ? "s88/Unit/mapping/runtime-targets.nix",
    }:
    let
      nodeInterfaces = forwardingNodeInterfacesForUnit {
        inherit cpm unitName file;
      };

      backingRef =
        if iface ? backingRef && builtins.isAttrs iface.backingRef then iface.backingRef else { };

      backingRefIdTail =
        if backingRef ? id && builtins.isString backingRef.id then
          lastStringSegment "::" backingRef.id
        else
          null;

      candidateKeys = lib.unique (
        lib.filter builtins.isString [
          ifName
          (iface.sourceInterface or null)
          (if backingRef ? name && builtins.isString backingRef.name then backingRef.name else null)
          backingRefIdTail
        ]
      );

      matchedKeys = lib.filter (candidateKey: builtins.hasAttr candidateKey nodeInterfaces) candidateKeys;
    in
    if matchedKeys == [ ] then
      { }
    else if builtins.length matchedKeys == 1 then
      nodeInterfaces.${builtins.head matchedKeys}
    else
      throw ''
        ${file}: multiple semantic forwarding interfaces matched runtime interface '${ifName}' for unit '${unitName}'

        matched keys:
        ${builtins.toJSON matchedKeys}
      '';
in
{
  inherit
    attrPathOrNull
    lastStringSegment
    forwardingModelFromCpm
    forwardingSiteForUnit
    forwardingNodeInterfacesForUnit
    semanticInterfaceForUnit
    ;
}
