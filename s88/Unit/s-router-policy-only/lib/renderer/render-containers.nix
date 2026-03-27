{
  lib,
  inventory,
  nodeName,
  hostName,
  cpm ? null,
}:

let
  validated = import ../inventory/validate.nix {
    inherit
      lib
      inventory
      nodeName
      hostName
      cpm
      ;
  };

  listInvariants = import ../list-invariants.nix { inherit lib; };
  inherit (listInvariants) duplicates;

  shortenIfName =
    name:
    if lib.stringLength name <= 15 then
      name
    else
      "if${builtins.substring 0 13 (builtins.hashString "sha256" name)}";

  node =
    if validated ? realization && validated.realization ? nodes && lib.hasAttr hostName validated.realization.nodes then
      validated.realization.nodes.${hostName}
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: container realization node missing
        nodeName: ${nodeName}
      '';

  ports =
    if node ? ports && builtins.isAttrs node.ports then
      node.ports
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: container realization ports missing
        nodeName: ${nodeName}
      '';

  portNames = lib.sort builtins.lessThan (builtins.attrNames ports);

  portLinks = map (p: ports.${p}.link) portNames;

  cpmData =
    if cpm == null then
      { }
    else
      cpm.control_plane_model.data or { };

  siteEntries =
    lib.concatMap (
      enterpriseName:
      let
        enterprise = cpmData.${enterpriseName};
      in
      map (siteName: enterprise.${siteName}) (lib.sort builtins.lessThan (builtins.attrNames enterprise))
    ) (lib.sort builtins.lessThan (builtins.attrNames cpmData));

  runtimeTargets =
    lib.foldl' (acc: site: acc // (site.runtimeTargets or { })) { } siteEntries;

  runtimeTarget =
    if lib.hasAttr nodeName runtimeTargets then
      runtimeTargets.${nodeName}
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime target missing
        nodeName: ${nodeName}
      '';

  interfaces =
    if runtimeTarget ? effectiveRuntimeRealization && runtimeTarget.effectiveRuntimeRealization ? interfaces then
      runtimeTarget.effectiveRuntimeRealization.interfaces
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interfaces missing
        nodeName: ${nodeName}
      '';

  interfaceNamesSorted = lib.sort builtins.lessThan (builtins.attrNames interfaces);

  interfaceEntries = map (
    runtimeIfName:
    let
      runtimeIf = interfaces.${runtimeIfName};
      backingRef = runtimeIf.backingRef or { };
      sourceRenderedIfName =
        if runtimeIf ? renderedIfName && runtimeIf.renderedIfName != "" then
          runtimeIf.renderedIfName
        else
          abort ''
            renderer/lib/renderer/render-containers.nix
            hostname: ${hostName}
            runtimeIfName: ${runtimeIfName}
            linkName: n/a
            error: renderedIfName missing
            nodeName: ${nodeName}
          '';
    in
    {
      inherit runtimeIfName runtimeIf backingRef sourceRenderedIfName;
      renderedIfName = shortenIfName sourceRenderedIfName;
      linkName =
        if (backingRef.kind or null) == "link" && (backingRef.name or "") != "" then
          backingRef.name
        else
          null;
    }
  ) interfaceNamesSorted;

  interfaceLinks = map (entry: entry.linkName) (lib.filter (entry: entry.linkName != null) interfaceEntries);

  _uniqueInterfaceNames =
    let
      dup = duplicates (map (entry: entry.renderedIfName) interfaceEntries);
    in
    if dup != [ ] then
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate rendered interface names
        duplicateNames: ${builtins.toJSON dup}
        nodeName: ${nodeName}
      ''
    else
      true;

  _uniqueInterfaceLinks =
    let
      dup = duplicates interfaceLinks;
    in
    if dup != [ ] then
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: duplicate runtime interface links
        duplicateLinks: ${builtins.toJSON dup}
        nodeName: ${nodeName}
      ''
    else
      true;

  _linkCoverage =
    let
      missingLinks = lib.filter (linkName: !(builtins.elem linkName portLinks)) interfaceLinks;
      extraLinks = lib.filter (linkName: !(builtins.elem linkName interfaceLinks)) portLinks;
    in
    if missingLinks != [ ] || extraLinks != [ ] then
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: n/a
        error: runtime interface to realization port link coverage mismatch
        missingLinks: ${builtins.toJSON missingLinks}
        extraLinks: ${builtins.toJSON extraLinks}
        nodeName: ${nodeName}
      ''
    else
      true;

  bridgeForLink =
    linkName:
    let
      matches = lib.filter (
        portName:
        let
          port = ports.${portName};
        in
        (port.link or null) == linkName
      ) portNames;
      selectedPortName =
        if builtins.length matches == 1 then
          builtins.elemAt matches 0
        else if builtins.length matches == 0 then
          abort ''
            renderer/lib/renderer/render-containers.nix
            hostname: ${hostName}
            runtimeIfName: n/a
            linkName: ${linkName}
            error: no realization port found for runtime link
            nodeName: ${nodeName}
          ''
        else
          abort ''
            renderer/lib/renderer/render-containers.nix
            hostname: ${hostName}
            runtimeIfName: n/a
            linkName: ${linkName}
            error: multiple realization ports found for runtime link
            matches: ${builtins.toJSON matches}
            nodeName: ${nodeName}
          '';
      port = ports.${selectedPortName};
    in
    if port ? attach && (port.attach.kind or null) == "bridge" && (port.attach.bridge or "") != "" then
      port.attach.bridge
    else
      abort ''
        renderer/lib/renderer/render-containers.nix
        hostname: ${hostName}
        runtimeIfName: n/a
        linkName: ${linkName}
        error: realization port is not bridge-backed
        nodeName: ${nodeName}
      '';

  bridgeEntries = lib.filter (entry: entry.linkName != null) interfaceEntries;
in
{
  extraVeths = builtins.listToAttrs (
    map (
      entry:
      {
        name = entry.renderedIfName;
        value = {
          hostBridge = bridgeForLink entry.linkName;
        };
      }
    ) bridgeEntries
  );
}
