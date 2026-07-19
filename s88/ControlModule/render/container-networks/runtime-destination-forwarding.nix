{ lib, pairs }:

lib.concatMap
  (
    pair:
    let
      destinations = pair.destinationRuntimeAddresses or [ ];
      matches = pair.matches or [ ];
      destination = if builtins.length destinations == 1 then builtins.head destinations else { };
      match = if builtins.length matches == 1 then builtins.head matches else { };
      dports = match.dports or [ ];
      valid =
        builtins.isAttrs pair
        && builtins.length destinations == 1
        && builtins.isAttrs destination
        && (destination.sourceClass or null) == "protected"
        && builtins.isString (destination.sourceFile or null)
        && lib.hasPrefix "/run/secrets/" destination.sourceFile
        && builtins.isString (destination.interfaceIdentifier or null)
        && builtins.isInt (destination.delegatedPrefixLength or null)
        && builtins.isInt (destination.perTenantPrefixLength or null)
        && builtins.isInt (destination.slot or null)
        && (destination.targetPrefixLength or null) == 128
        && builtins.length (pair."in" or [ ]) == 1
        && builtins.length (pair."out" or [ ]) == 1
        && builtins.length matches == 1
        && (match.family or null) == "ipv6"
        && builtins.elem (match.proto or null) [ "tcp" "udp" ]
        && builtins.length dports == 1
        && builtins.isInt (builtins.head dports)
        && builtins.isString (pair.comment or null)
        && pair.comment != ""
        && (pair.returnBehavior or null) == "stateful-return"
        && (pair.translationMode or null) == "none"
        && (pair.sourcePreservation or null) == "preserve-source"
        && (pair.destinationTranslation or null) == false;
    in
    if destinations == [ ] then
      [ ]
    else if !valid then
      throw "FS-230-HDS-010-SDS-010-SMS-040: incomplete protected runtime IPv6 destination forwarding contract"
    else
      [ {
        inherit (destination)
          sourceFile
          interfaceIdentifier
          delegatedPrefixLength
          perTenantPrefixLength
          slot
          targetPrefixLength
          ;
        inIf = builtins.head pair."in";
        outIf = builtins.head pair."out";
        protocol = match.proto;
        destinationPort = builtins.head dports;
        action = pair.action or (throw "FS-230-HDS-010-SDS-010-SMS-040: runtime destination rule lacks action");
        comment = builtins.substring 0 128 pair.comment;
        family = 6;
        inherit (pair)
          returnBehavior
          translationMode
          sourcePreservation
          destinationTranslation
          ;
      } ]
  )
  pairs
