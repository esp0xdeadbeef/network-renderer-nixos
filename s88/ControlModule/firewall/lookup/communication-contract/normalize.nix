{ lib }:

let
  isNonEmptyAttrs = value: builtins.isAttrs value && value != { };

  validServices =
    services:
    builtins.isList services
    && lib.all
      (
        service: builtins.isAttrs service && builtins.isString (service.name or null) && service.name != ""
      )
      services;
in
rec {
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

  firstNonEmptyAttrs =
    candidates:
    let
      matches = lib.filter isNonEmptyAttrs candidates;
    in
    if matches == [ ] then { } else builtins.head matches;

  canonicalCommunicationContract =
    attrs:
    if
      builtins.isAttrs attrs
      && (
        (attrs ? relations && builtins.isList attrs.relations)
        || (attrs ? allowedRelations && builtins.isList attrs.allowedRelations)
        || (attrs ? services && builtins.isList attrs.services)
        || (attrs ? trafficTypes && builtins.isList attrs.trafficTypes)
        || (attrs ? interfaceTags && builtins.isAttrs attrs.interfaceTags)
        || (attrs ? ownership && builtins.isAttrs attrs.ownership)
      )
    then
      {
        relations =
          if attrs ? relations && builtins.isList attrs.relations then
            attrs.relations
          else if attrs ? allowedRelations && builtins.isList attrs.allowedRelations then
            attrs.allowedRelations
          else
            [ ];
        services = if attrs ? services && builtins.isList attrs.services then attrs.services else [ ];
        trafficTypes =
          if attrs ? trafficTypes && builtins.isList attrs.trafficTypes then attrs.trafficTypes else [ ];
        interfaceTags =
          if attrs ? interfaceTags && builtins.isAttrs attrs.interfaceTags then attrs.interfaceTags else { };
        ownership = if attrs ? ownership && builtins.isAttrs attrs.ownership then attrs.ownership else { };
      }
    else
      { };

  mergeCommunicationContracts =
    primary: secondary:
    let
      p = canonicalCommunicationContract primary;
      s = canonicalCommunicationContract secondary;
    in
    {
      relations = if p.relations or [ ] != [ ] then p.relations else s.relations or [ ];
      services =
        if validServices (p.services or [ ]) && p.services or [ ] != [ ] then
          p.services
        else
          s.services or [ ];
      trafficTypes = if p.trafficTypes or [ ] != [ ] then p.trafficTypes else s.trafficTypes or [ ];
      interfaceTags = if p.interfaceTags or { } != { } then p.interfaceTags else s.interfaceTags or { };
      ownership = if p.ownership or { } != { } then p.ownership else s.ownership or { };
    };
}
