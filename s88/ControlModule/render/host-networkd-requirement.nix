{}:

{ renderedNetdevs ? { }
, renderedNetworks ? { }
, renderedContainers ? { }
, mgmtManageDhcp ? false
,
}:

let
  isNonEmptyString = value: builtins.isString value && value != "";

  containerHasHostBridge =
    container:
    let
      extraVeths =
        if builtins.isAttrs container && builtins.isAttrs (container.extraVeths or null) then
          container.extraVeths
        else
          { };

      hasPrimaryBridge =
        builtins.isAttrs container
        && isNonEmptyString (container.hostBridge or null);

      hasExtraVethBridge =
        builtins.any
          (
            veth:
            builtins.isAttrs veth
            && isNonEmptyString (veth.hostBridge or null)
          )
          (builtins.attrValues extraVeths);
    in
    hasPrimaryBridge || hasExtraVethBridge;
in
mgmtManageDhcp
|| builtins.attrNames renderedNetdevs != [ ]
|| builtins.attrNames renderedNetworks != [ ]
|| builtins.any containerHasHostBridge (builtins.attrValues renderedContainers)
