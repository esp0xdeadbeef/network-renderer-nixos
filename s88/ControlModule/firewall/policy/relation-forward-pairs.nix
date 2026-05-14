{
  lib,
  communicationContract ? { },
  endpointMap ? { },
}:

let
  resolveEndpoint =
    if endpointMap ? resolveEndpoint && builtins.isFunction endpointMap.resolveEndpoint then
      endpointMap.resolveEndpoint
    else
      (_: [ ]);

  resolveRelationEndpoint =
    if endpointMap ? resolveRelationEndpoint && builtins.isFunction endpointMap.resolveRelationEndpoint then
      endpointMap.resolveRelationEndpoint
    else
      (_: resolveEndpoint);

  allowForwardPair =
    if endpointMap ? allowForwardPair && builtins.isFunction endpointMap.allowForwardPair then
      endpointMap.allowForwardPair
    else
      (_: _: _: true);

  relationNameOf =
    relation:
    if relation ? id && builtins.isString relation.id then
      relation.id
    else if
      builtins.isAttrs (relation.source or null)
      && relation.source ? id
      && builtins.isString relation.source.id
    then
      relation.source.id
    else if relation ? name && builtins.isString relation.name then
      relation.name
    else
      builtins.toJSON relation;

  relations =
    if communicationContract ? relations && builtins.isList communicationContract.relations then
      lib.filter builtins.isAttrs communicationContract.relations
    else
      [ ];
in
lib.concatMap (
  relation:
  let
    action = if (relation.action or "allow") == "deny" then "drop" else "accept";
    fromInterfaces = resolveRelationEndpoint relation (relation.from or null);
    toInterfaces = resolveRelationEndpoint relation (relation.to or null);
    trafficType =
      if relation ? trafficType && builtins.isString relation.trafficType then
        relation.trafficType
      else
        "any";
    comment = relationNameOf relation;
  in
  lib.concatMap (
    fromIf:
    map
      (toIf: {
        "in" = [ fromIf ];
        "out" = [ toIf ];
        inherit action trafficType comment;
      })
      (lib.filter (toIf: allowForwardPair relation fromIf toIf) toInterfaces)
  ) fromInterfaces
) relations
