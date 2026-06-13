{ lib }:

# NOTE: CMC-NIXOS-INTENT-CLEANUP: renamed from inventory tree walks to source-based lookups.
# Per SMS-100/SMS-101, renderers consume CPM output. These helpers accept any source
# container with .realization/.deployment/.render structures — whether from CPM or
# CPM-preserved inventory. The parameter is now named 'source' instead of 'inventory'.
rec {
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  isNonEmptyAttrs = value: builtins.isAttrs value && sortedAttrNames value != [ ];

  realizationNodesFor =
    source:
    if
      source ? realization
      && builtins.isAttrs source.realization
      && source.realization ? nodes
      && builtins.isAttrs source.realization.nodes
    then
      source.realization.nodes
    else
      { };

  deploymentHostsFor =
    source:
    if
      source ? deployment
      && builtins.isAttrs source.deployment
      && source.deployment ? hosts
      && builtins.isAttrs source.deployment.hosts
    then
      source.deployment.hosts
    else
      { };

  renderHostsFor =
    source:
    if
      source ? render
      && builtins.isAttrs source.render
      && source.render ? hosts
      && builtins.isAttrs source.render.hosts
    then
      source.render.hosts
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
    source: predicate:
    let
      realizationNodes = realizationNodesFor source;
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
