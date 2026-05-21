{ lib }:

rec {
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  isNonEmptyAttrs = value: builtins.isAttrs value && sortedAttrNames value != [ ];

  realizationNodesFor =
    inventory:
    if
      inventory ? realization
      && builtins.isAttrs inventory.realization
      && inventory.realization ? nodes
      && builtins.isAttrs inventory.realization.nodes
    then
      inventory.realization.nodes
    else
      { };

  deploymentHostsFor =
    inventory:
    if
      inventory ? deployment
      && builtins.isAttrs inventory.deployment
      && inventory.deployment ? hosts
      && builtins.isAttrs inventory.deployment.hosts
    then
      inventory.deployment.hosts
    else
      { };

  renderHostsFor =
    inventory:
    if
      inventory ? render
      && builtins.isAttrs inventory.render
      && inventory.render ? hosts
      && builtins.isAttrs inventory.render.hosts
    then
      inventory.render.hosts
    else
      { };

  selectAttrs =
    names: attrs:
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = attrs.${name};
        })
        (lib.filter (name: builtins.hasAttr name attrs) names)
    );

  matchingNodesBy =
    inventory: predicate:
    let
      realizationNodes = realizationNodesFor inventory;
    in
    builtins.listToAttrs (
      map
        (nodeName: {
          name = nodeName;
          value = realizationNodes.${nodeName};
        })
        (
          lib.filter (nodeName: predicate nodeName realizationNodes.${nodeName}) (
            sortedAttrNames realizationNodes
          )
        )
    );

  hostNamesFromNodes =
    nodes:
    lib.unique (
      lib.filter builtins.isString (
        map
          (
            nodeName:
            let
              node = nodes.${nodeName};
            in
            if node ? host && builtins.isString node.host then node.host else null
          )
          (sortedAttrNames nodes)
      )
    );
}
