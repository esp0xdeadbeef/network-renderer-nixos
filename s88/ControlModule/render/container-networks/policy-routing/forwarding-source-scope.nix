{ lib, forwardingRulesResolved }:

let
  sourcePrefixFromRule =
    rule: value:
    let
      prefix = if builtins.isString value then value else value.prefix or "";
      family =
        if builtins.isAttrs value && (value.family or null) == 6 then
          6
        else if builtins.isAttrs value && (value.family or null) == 4 then
          4
        else if builtins.isString prefix && lib.hasInfix ":" prefix then
          6
        else if builtins.isInt (rule.family or null) then
          rule.family
        else
          4;
      origin = if builtins.isAttrs value && builtins.isAttrs (value.origin or null) then value.origin else null;
    in
    if !(builtins.isString prefix) || prefix == "" then
      null
    else
      { inherit family prefix; }
      // lib.optionalAttrs (origin != null) { inherit origin; };
in
{
  forInterface =
    interfaceName:
    builtins.foldl'
      (
        acc: rule:
        if
          builtins.isAttrs rule
          && (rule.action or null) == "accept"
          && (rule.fromInterface or null) == interfaceName
        then
          {
            sourceFiles =
              acc.sourceFiles
              ++ (
                if builtins.isInt (rule.family or null) && builtins.isList (rule.sourceFiles or null) then
                  map (sourceFile: {
                    family = rule.family;
                    inherit sourceFile;
                  }) (lib.filter (sourceFile: builtins.isString sourceFile && sourceFile != "") rule.sourceFiles)
                else
                  [ ]
              );
            staticPrefixes =
              acc.staticPrefixes
              ++ (
                if builtins.isList (rule.sourcePrefixes or null) then
                  lib.filter (prefix: prefix != null) (map (sourcePrefixFromRule rule) rule.sourcePrefixes)
                else
                  [ ]
              );
          }
        else
          acc
      )
      {
        sourceFiles = [ ];
        staticPrefixes = [ ];
      }
      forwardingRulesResolved;
}
