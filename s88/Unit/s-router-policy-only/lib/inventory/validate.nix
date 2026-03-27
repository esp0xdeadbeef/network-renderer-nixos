{
  lib,
  inventory,
  nodeName ? null,
  hostName ? null,
  cpm ? null,
}:

let
  _inventory = import ./load.nix { inherit inventory; };

  listInvariants = import ../list-invariants.nix { inherit lib; };
  inherit (listInvariants) duplicates;

  hostNames = builtins.attrNames _inventory.deployment.hosts;
  nodeNames = builtins.attrNames _inventory.realization.nodes;

  cpmNodeNames =
    if cpm == null then
      [ ]
    else if cpm ? nodes then
      builtins.attrNames cpm.nodes
    else if cpm ? units then
      builtins.attrNames cpm.units
    else if cpm ? logical && cpm.logical ? nodes then
      builtins.attrNames cpm.logical.nodes
    else
      [ ];

  cpmLinkNames =
    if cpm == null then
      [ ]
    else if cpm ? links then
      builtins.attrNames cpm.links
    else if cpm ? logical && cpm.logical ? links then
      builtins.attrNames cpm.logical.links
    else
      [ ];

  validateNode =
    n:
    let
      node = _inventory.realization.nodes.${n};
      ports =
        if node ? ports && builtins.isAttrs node.ports then
          node.ports
        else
          abort "renderer: realization.nodes.${n}.ports is missing";

      portNames = builtins.attrNames ports;

      ifaceNames = map (p: ports.${p}.interface.name) portNames;

      _host =
        if !(node ? host) then
          abort "renderer: realization.nodes.${n}.host is missing"
        else if !builtins.elem node.host hostNames then
          abort "renderer: realization.nodes.${n}.host '${node.host}' does not exist under deployment.hosts"
        else
          node.host;

      _portsValidated = map (
        p:
        let
          port = ports.${p};
        in
        if !(port ? link) then
          abort "renderer: realization.nodes.${n}.ports.${p}.link is missing"
        else if !(port ? attach) || !builtins.isAttrs port.attach then
          abort "renderer: realization.nodes.${n}.ports.${p}.attach is missing"
        else if !(port.attach ? kind) then
          abort "renderer: realization.nodes.${n}.ports.${p}.attach.kind is missing"
        else if port.attach.kind == "bridge" && !(port.attach ? bridge) then
          abort "renderer: realization.nodes.${n}.ports.${p}.attach.bridge is missing"
        else if !(port ? interface) || !builtins.isAttrs port.interface then
          abort "renderer: realization.nodes.${n}.ports.${p}.interface is missing"
        else if !(port.interface ? name) || port.interface.name == "" then
          abort "renderer: realization.nodes.${n}.ports.${p}.interface.name is missing"
        else if cpmLinkNames != [ ] && !(builtins.elem port.link cpmLinkNames) then
          abort "renderer: realization.nodes.${n}.ports.${p}.link '${port.link}' is not present in CPM"
        else
          true
      ) portNames;

      _ifaceDup =
        let
          dup = duplicates ifaceNames;
        in
        if dup != [ ] then
          abort "renderer: realization.nodes.${n} has duplicate interface names: ${lib.concatStringsSep ", " dup}"
        else
          true;

      _cpmNode =
        if cpmNodeNames != [ ] && !(builtins.elem n cpmNodeNames) then
          abort "renderer: realization node '${n}' is not present in CPM"
        else
          true;
    in
    true;

  _allNodesValidated = map validateNode nodeNames;

  validateHost =
    h:
    let
      host = _inventory.deployment.hosts.${h};

      uplinkNames =
        if host ? uplinks && builtins.isAttrs host.uplinks then
          builtins.attrNames host.uplinks
        else
          abort "renderer: deployment.hosts.${h}.uplinks is missing";

      uplinkBridges = map (u: host.uplinks.${u}.bridge) uplinkNames;

      transitBridges =
        if host ? transitBridges && builtins.isAttrs host.transitBridges then
          map (n: host.transitBridges.${n}.name) (builtins.attrNames host.transitBridges)
        else
          [ ];

      bridgeDup = duplicates (uplinkBridges ++ transitBridges);

      _uplinksValidated = map (
        u:
        let
          uplink = host.uplinks.${u};
          mode = uplink.mode or "";
        in
        if !(uplink ? parent) || uplink.parent == "" then
          abort "renderer: deployment.hosts.${h}.uplinks.${u}.parent is missing"
        else if !(uplink ? bridge) || uplink.bridge == "" then
          abort "renderer: deployment.hosts.${h}.uplinks.${u}.bridge is missing"
        else if !(uplink ? mode) || uplink.mode == "" then
          abort "renderer: deployment.hosts.${h}.uplinks.${u}.mode is missing"
        else if mode == "vlan" && !(uplink ? vlan) then
          abort "renderer: deployment.hosts.${h}.uplinks.${u}.vlan is required when mode = vlan"
        else
          true
      ) uplinkNames;

      _bridgeDup =
        if bridgeDup != [ ] then
          abort "renderer: deployment.hosts.${h} has colliding bridge names: ${lib.concatStringsSep ", " bridgeDup}"
        else
          true;
    in
    true;

  _allHostsValidated = map validateHost hostNames;

  _selectedNode =
    if nodeName != null && !builtins.elem nodeName nodeNames then
      abort "renderer: realization for node '${nodeName}' is missing"
    else
      true;

  _selectedHost =
    if hostName != null && !builtins.elem hostName hostNames then
      abort "renderer: deployment host '${hostName}' is missing"
    else
      true;
in
_inventory
