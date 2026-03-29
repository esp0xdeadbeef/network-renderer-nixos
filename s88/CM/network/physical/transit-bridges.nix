{
  lib,
  deploymentHostName,
  deploymentHost,
  realizationNodes,
}:

let
  hostNaming = import ../../../../lib/host-naming.nix { inherit lib; };

  synthesizedTransitLinks = lib.unique (
    lib.concatMap (
      nodeName:
      let
        node = realizationNodes.${nodeName};
        ports = if node ? ports && builtins.isAttrs node.ports then node.ports else { };
      in
      if (node.host or null) == deploymentHostName then
        lib.concatMap (
          portName:
          let
            port = ports.${portName};
          in
          lib.optionals
            (
              builtins.isAttrs port
              && port ? link
              && builtins.isString port.link
              && port ? attach
              && builtins.isAttrs port.attach
              && (port.attach.kind or null) == "direct"
            )
            [
              port.link
            ]
        ) (builtins.attrNames ports)
      else
        [ ]
    ) (builtins.attrNames realizationNodes)
  );

  synthesizedTransitBridgeNameMap = hostNaming.ensureUnique synthesizedTransitLinks;

  transitBridges =
    if !(deploymentHost ? transitBridges) then
      builtins.listToAttrs (
        map (linkName: {
          name = linkName;
          value = {
            name = synthesizedTransitBridgeNameMap.${linkName};
          };
        }) synthesizedTransitLinks
      )
    else if builtins.isAttrs deploymentHost.transitBridges then
      deploymentHost.transitBridges
    else
      throw ''
        s88/CM/network/physical/transit-bridges.nix: deployment host '${deploymentHostName}' has non-attr transitBridges

        deployment host:
        ${builtins.toJSON deploymentHost}
      '';
in
{
  inherit transitBridges;
}
