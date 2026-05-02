{ lib }:

let
  stripPrefixLength =
    value:
    if !(builtins.isString value) then
      null
    else
      let parts = lib.splitString "/" value;
      in if builtins.length parts > 0 then builtins.elemAt parts 0 else null;
in
{
  firstAddressMatching =
    { addresses, predicate }:
    let
      values =
        if builtins.isList addresses then
          lib.filter (
            value: builtins.isString value && predicate value && (stripPrefixLength value) != null
          ) addresses
        else
          [ ];
    in
    if values == [ ] then null else stripPrefixLength (builtins.head values);
}
