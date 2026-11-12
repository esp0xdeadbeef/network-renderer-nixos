{ lib }:

let
  requiredLimits = [
    "requesterScope"
    "mappingRange"
    "lifetime"
    "auditBehavior"
    "conflictHandling"
    "publicExposureLimits"
  ];

  protocols = [
    "upnp-igd"
    "nat-pmp"
    "pcp"
  ];

  missingLimitsOf = relationship: builtins.filter (field: !(relationship ? ${field})) requiredLimits;

  validateRelationship =
    traceId: relationship:
    let
      missing = missingLimitsOf relationship;
    in
    if !(builtins.isAttrs relationship) then
      throw "${traceId}: port-mapping relationship must be an attribute set"
    else if missing != [ ] then
      throw "${traceId}: port-mapping relationship cannot express: ${builtins.concatStringsSep ", " missing}; a grant must state every limit rather than default it"
    else
      true;
in
{
  inherit protocols requiredLimits;

  serviceStateFor =
    traceId: relationships:
    let
      granted = lib.filter (
        name:
        let
          rel = relationships.${name} or null;
        in
        builtins.isAttrs rel && (rel.protocol or null) != null
      ) (builtins.attrNames relationships);
      stateOf =
        protocol:
        let
          matched = lib.filter (name: (relationships.${name}.protocol or null) == protocol) granted;
        in
        {
          enable = matched != [ ];
          modeled = matched != [ ];
          grants = map (
            name:
            builtins.seq (validateRelationship traceId relationships.${name}) {
              inherit name;
              inherit (relationships.${name})
                requesterScope
                mappingRange
                lifetime
                auditBehavior
                conflictHandling
                publicExposureLimits
                ;
            }
          ) matched;
        };
    in
    builtins.listToAttrs (
      map (protocol: {
        name = protocol;
        value = stateOf protocol;
      }) protocols
    );

  mappingAuthorityFor =
    traceId: relationships: name:
    let
      rel = relationships.${name} or null;
    in
    if rel == null then
      throw "${traceId}: no port-mapping relationship models '${name}'; discovery is not mapping authority"
    else
      builtins.seq (validateRelationship traceId rel) rel;
}
