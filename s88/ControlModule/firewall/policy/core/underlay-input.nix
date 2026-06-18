{ lib
, catalog
,
}:

let
  isExternal =
    endpoint: builtins.isAttrs endpoint && (endpoint.kind or null) == "external";

  trafficTypeMatches =
    trafficTypeName:
    if trafficTypeName == null || trafficTypeName == "any" then
      [ ]
    else if builtins.hasAttr trafficTypeName catalog.trafficTypeDefinitions then
      let
        trafficType = catalog.trafficTypeDefinitions.${trafficTypeName};
      in
      if builtins.isList (trafficType.match or null) then trafficType.match else [ ]
    else
      [ ];

  isExternalUnderlayRelation =
    relation:
    let
      action = relation.action or (throw "FS-310-HDS-030-SDS-010-SMS-111: relation.action required by CPM provider contract, cannot default to 'allow'");
    in
    builtins.isAttrs relation
    && action == "allow"
    && isExternal (relation.from or null)
    && isExternal (relation.to or null)
    && builtins.isString (relation.trafficType or null);

  udpPortsForRelation =
    relation:
    lib.concatMap
      (
        match:
        if builtins.isAttrs match && (match.proto or null) == "udp" then match.dports or [ ] else [ ]
      )
      (trafficTypeMatches relation.trafficType);
in
{
  udpPorts =
    lib.unique (
      lib.concatMap udpPortsForRelation (builtins.filter isExternalUnderlayRelation catalog.allowRelations)
    );
}
