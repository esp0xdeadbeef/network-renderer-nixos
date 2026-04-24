{ lib }:

let
  requireAttr =
    path: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos overlay-runtime: missing attrset at ${path}";

  requireString =
    path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos overlay-runtime: missing string at ${path}";

  stripPrefixLength =
    cidr:
    let
      match = builtins.match "([^/]+)/[0-9]+" cidr;
    in
    if match == null then
      throw "network-renderer-nixos overlay-runtime: expected CIDR, got ${builtins.toJSON cidr}"
    else
      builtins.head match;

  readPrefixLength =
    cidr:
    let
      match = builtins.match "[^/]+/([0-9]+)" cidr;
    in
    if match == null then
      throw "network-renderer-nixos overlay-runtime: expected CIDR prefix length, got ${builtins.toJSON cidr}"
    else
      builtins.fromJSON (builtins.head match);

  withPrefixLength =
    cidr: prefixLength: "${stripPrefixLength cidr}/${builtins.toString prefixLength}";

  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);
in
{
  nebulaPlan =
    {
      renderedHostNetwork,
      inventory ? { },
      caName ? "s-router-test-lab",
    }:
    let
      renderedSites = renderedHostNetwork.sites or { };
      inventorySites = ((inventory.controlPlane or { }).sites or { });

      overlayEntries = builtins.concatLists (
        map (
          enterpriseName:
          let
            enterpriseInventory =
              requireAttr "inventory.controlPlane.sites.${enterpriseName}"
                inventorySites.${enterpriseName};
          in
          builtins.concatLists (
            map (
              siteName:
              let
                siteInventory =
                  requireAttr "inventory.controlPlane.sites.${enterpriseName}.${siteName}"
                    enterpriseInventory.${siteName};
                overlays = siteInventory.overlays or { };
              in
              map (
                overlayName:
                let
                  overlayInventory =
                    requireAttr "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}"
                      overlays.${overlayName};
                in
                {
                  inherit
                    enterpriseName
                    siteName
                    overlayName
                    overlayInventory
                    ;
                }
              ) (sortedAttrNames overlays)
            ) (sortedAttrNames enterpriseInventory)
          )
        ) (sortedAttrNames inventorySites)
      );

      nebulaOverlayEntries = lib.filter (
        entry:
        let
          provider = entry.overlayInventory.provider or null;
        in
        builtins.isString provider && provider == "nebula"
      ) overlayEntries;

      overlayPlans = builtins.listToAttrs (
        map (
          entry:
          let
            enterpriseName = entry.enterpriseName;
            siteName = entry.siteName;
            overlayName = entry.overlayName;
            overlayId = "${enterpriseName}::${siteName}::${overlayName}";

            renderedEnterprise = requireAttr "renderedHostNetwork.sites.${enterpriseName}" (
              renderedSites.${enterpriseName} or null
            );
            renderedSite = requireAttr "renderedHostNetwork.sites.${enterpriseName}.${siteName}" (
              renderedEnterprise.${siteName} or null
            );
            renderedOverlays = requireAttr "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays" (
              renderedSite.overlays or null
            );
            renderedOverlay =
              requireAttr "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}"
                (renderedOverlays.${overlayName} or null);

            overlayNodes =
              requireAttr "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes"
                (renderedOverlay.nodes or null);
            nebula =
              requireAttr "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula"
                (renderedOverlay.nebula or null);
            lighthouse =
              requireAttr
                "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula.lighthouse"
                (nebula.lighthouse or null);
            lighthouseNodeName =
              requireString
                "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.nebula.lighthouse.node"
                (lighthouse.node or null);
            lighthouseNode =
              requireAttr
                "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes.${lighthouseNodeName}"
                (overlayNodes.${lighthouseNodeName} or null);
            ipam =
              requireAttr "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.ipam"
                (renderedOverlay.ipam or null);
            ipam4 =
              requireAttr
                "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.ipam.ipv4"
                (ipam.ipv4 or null);
            ipam6 =
              requireAttr
                "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.ipam.ipv6"
                (ipam.ipv6 or null);
            prefixLength4 = readPrefixLength (
              requireString "${enterpriseName}.${siteName}.${overlayName}.ipam.ipv4.prefix" (ipam4.prefix or null)
            );
            prefixLength6 = readPrefixLength (
              requireString "${enterpriseName}.${siteName}.${overlayName}.ipam.ipv6.prefix" (ipam6.prefix or null)
            );
            runtimeNodes = entry.overlayInventory.runtimeNodes or { };

            nodePlans = builtins.listToAttrs (
              map (
                nodeName:
                let
                  runtimeNode =
                    requireAttr
                      "inventory.controlPlane.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.runtimeNodes.${nodeName}"
                      runtimeNodes.${nodeName};
                  renderedNode =
                    requireAttr
                      "renderedHostNetwork.sites.${enterpriseName}.${siteName}.overlays.${overlayName}.nodes.${nodeName}"
                      (overlayNodes.${nodeName} or null);
                in
                {
                  name = nodeName;
                  value = {
                    inherit
                      enterpriseName
                      siteName
                      overlayName
                      overlayId
                      ;
                    overlayAddresses = [
                      (withPrefixLength (requireString "${nodeName}.addr4" (renderedNode.addr4 or null)) prefixLength4)
                      (withPrefixLength (requireString "${nodeName}.addr6" (renderedNode.addr6 or null)) prefixLength6)
                    ];
                    groups =
                      if builtins.isList (runtimeNode.groups or null) then
                        lib.filter builtins.isString runtimeNode.groups
                      else
                        [ ];
                    unsafeRoutes =
                      if builtins.isList (runtimeNode.unsafeRoutes or null) then
                        lib.filter builtins.isAttrs runtimeNode.unsafeRoutes
                      else
                        [ ];
                    service = (runtimeNode.service or { }) // {
                      name = (runtimeNode.service.name or "nebula-runtime");
                      interface = (runtimeNode.service.interface or "nebula1");
                    };
                    materialization = builtins.removeAttrs runtimeNode [
                      "groups"
                      "unsafeRoutes"
                      "service"
                    ];
                    lighthouse = {
                      node = lighthouseNodeName;
                      endpoint = requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null);
                      endpoint6 = requireString "${overlayName}.nebula.lighthouse.endpoint6" (
                        lighthouse.endpoint6 or null
                      );
                      port = builtins.toString (lighthouse.port or 4242);
                      endpoints = [
                        "${requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null)}:${
                          builtins.toString (lighthouse.port or 4242)
                        }"
                        "[${requireString "${overlayName}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null)}]:${
                          builtins.toString (lighthouse.port or 4242)
                        }"
                      ];
                      overlayAddresses = [
                        (withPrefixLength (requireString "${lighthouseNodeName}.addr4" (
                          lighthouseNode.addr4 or null
                        )) prefixLength4)
                        (withPrefixLength (requireString "${lighthouseNodeName}.addr6" (
                          lighthouseNode.addr6 or null
                        )) prefixLength6)
                      ];
                      overlayIps = [
                        (stripPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)))
                        (stripPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)))
                      ];
                    };
                  };
                }
              ) (sortedAttrNames runtimeNodes)
            );
          in
          {
            name = overlayId;
            value = {
              type = "nebula";
              name = overlayName;
              inherit enterpriseName siteName overlayId;
              ca = {
                name = caName;
              };
              lighthouse = {
                node = lighthouseNodeName;
                endpoint = requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null);
                endpoint6 = requireString "${overlayName}.nebula.lighthouse.endpoint6" (
                  lighthouse.endpoint6 or null
                );
                port = builtins.toString (lighthouse.port or 4242);
                endpoints = [
                  "${requireString "${overlayName}.nebula.lighthouse.endpoint" (lighthouse.endpoint or null)}:${
                    builtins.toString (lighthouse.port or 4242)
                  }"
                  "[${requireString "${overlayName}.nebula.lighthouse.endpoint6" (lighthouse.endpoint6 or null)}]:${
                    builtins.toString (lighthouse.port or 4242)
                  }"
                ];
                overlayAddresses = [
                  (withPrefixLength (requireString "${lighthouseNodeName}.addr4" (
                    lighthouseNode.addr4 or null
                  )) prefixLength4)
                  (withPrefixLength (requireString "${lighthouseNodeName}.addr6" (
                    lighthouseNode.addr6 or null
                  )) prefixLength6)
                ];
                overlayIps = [
                  (stripPrefixLength (requireString "${lighthouseNodeName}.addr4" (lighthouseNode.addr4 or null)))
                  (stripPrefixLength (requireString "${lighthouseNodeName}.addr6" (lighthouseNode.addr6 or null)))
                ];
              };
              nodes = nodePlans;
            };
          }
        ) nebulaOverlayEntries
      );

      nodePlans = builtins.listToAttrs (
        builtins.concatLists (
          map (
            overlayId:
            map (nodeName: {
              name = nodeName;
              value = overlayPlans.${overlayId}.nodes.${nodeName};
            }) (sortedAttrNames overlayPlans.${overlayId}.nodes)
          ) (sortedAttrNames overlayPlans)
        )
      );
    in
    {
      overlays = overlayPlans;
      nodes = nodePlans;
    };
}
