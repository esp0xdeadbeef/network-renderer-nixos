{
  controlPlane, # The validated bundle's canonical collections: a SIBLING of the control-plane

  canonicalCollections ? { },
}:

let
  canonicalSites =
    (if builtins.isAttrs canonicalCollections then canonicalCollections else { }).canonicalSites or { };

  fromCanonical =
    if builtins.isAttrs (canonicalSites.byEnterprise or null) then
      canonicalSites.byEnterprise
    else
      null;
  data =
    if fromCanonical != null then
      fromCanonical
    else if builtins.isAttrs (controlPlane.control_plane_model or null) then
      controlPlane.control_plane_model.data or { }
    else
      { };
in
if !builtins.isAttrs data then
  { }
else
  builtins.mapAttrs (
    _enterprise: sites:
    if !builtins.isAttrs sites then
      { }
    else
      builtins.mapAttrs (
        _siteName: siteObj:
        if !builtins.isAttrs siteObj then
          { }
        else
          {
            ipv6 = siteObj.ipv6 or { };
            routing = siteObj.routing or { };
            transit = siteObj.transit or { };
          }
      ) sites
  ) data
