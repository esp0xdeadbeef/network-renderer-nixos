{ controlPlane }:

let
  data =
    if controlPlane ? control_plane_model && builtins.isAttrs controlPlane.control_plane_model then
      controlPlane.control_plane_model.data or { }
    else
      { };
in
if !builtins.isAttrs data then
  { }
else
  builtins.mapAttrs
    (
      _enterprise: sites:
      if !builtins.isAttrs sites then
        { }
      else
        builtins.mapAttrs
          (
            _siteName: siteObj:
            if !builtins.isAttrs siteObj then
              { }
            else
              {
                ipv6 = siteObj.ipv6 or { };
                routing = siteObj.routing or { };
                transit = siteObj.transit or { };
              }
          )
          sites
    )
    data
