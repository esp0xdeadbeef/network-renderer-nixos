{ lib
, pkgs
, renderedModel
, forwardingIntent ? { }
,
}:

let
  facts = import ./dns-services/facts.nix {
    inherit lib renderedModel forwardingIntent;
  };
in
if facts == null then
  { }
else
  let
    inherit (facts)
      listenAddresses
      allowFrom
      forwarders
      hasMixedForwarders
      localZones
      localRecords
      namespaceFallbackDecisions
      outgoingInterfaces
      recursionMode
      warningCodes
      localForwardZones
      requesterPolicies
      ;

    requesterAccessControl = lib.concatMap
      (policy:
        map
          (cidr: "${cidr} ${policy.action}")
          (lib.filter builtins.isString (policy.sourcePrefixes or [ ])))
      requesterPolicies;
    accessControl = lib.unique ((map (cidr: "${cidr} allow") allowFrom) ++ requesterAccessControl);
    namespaceFallbackZoneSettings =
      map (decision: "${decision.namespace} static") namespaceFallbackDecisions;
    localOnlyRootZoneSettings = lib.optional (recursionMode == "local-only") ". static";
    localZoneSettings =
      lib.unique (
        (map (zone: "${zone.name} ${zone.type or "static"}") localZones)
        ++ namespaceFallbackZoneSettings
        ++ localOnlyRootZoneSettings
      );
    localForwardZoneSettings = map
      (zone: {
        name = zone.name;
        "forward-addr" = zone.forwardTo;
        "forward-first" = zone.forwardFirst;
      })
      localForwardZones;
    localDataSettings = lib.concatMap
      (
        record:
        let
          name = record.name;
          a = if builtins.isList (record.a or null) then lib.filter builtins.isString record.a else [ ];
          aaaa =
            if builtins.isList (record.aaaa or null) then lib.filter builtins.isString record.aaaa else [ ];
        in
        (map (addr: "\"${name} IN A ${addr}\"") a) ++ (map (addr: "\"${name} IN AAAA ${addr}\"") aaaa)
      )
      localRecords;
    nft = import ./dns-services/nft-rules.nix { inherit lib pkgs facts; };
  in
  {
    warnings = map
      (code: "network-renderer-nixos DNS reproducibility warning ${code}; address material is intentionally omitted")
      warningCodes;

    services.unbound = {
      enable = true;
      enableRootTrustAnchor = recursionMode == "iterative";
      settings = {
        server = {
          interface = listenAddresses;
          "access-control" = accessControl;
          "do-ip4" = true;
          "do-ip6" = true;
          "infra-host-ttl" = 1;
          "infra-lame-ttl" = 1;
        }
        // lib.optionalAttrs hasMixedForwarders {
          "prefer-ip4" = true;
        }
        // lib.optionalAttrs (localZoneSettings != [ ]) {
          "local-zone" = localZoneSettings;
        }
        // lib.optionalAttrs (localDataSettings != [ ]) {
          "local-data" = localDataSettings;
        }
        // lib.optionalAttrs (outgoingInterfaces != [ ]) {
          "outgoing-interface" = outgoingInterfaces;
        };
        forward-zone =
          lib.optional (forwarders != [ ]) {
            name = ".";
            "forward-addr" = forwarders;
          }
          ++ localForwardZoneSettings;
        remote-control = {
          "control-enable" = true;
          "control-interface" = [
            "127.0.0.1"
            "::1"
          ];
        };
      };
    };

    systemd.services.unbound = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };

    systemd.services.nft-allow-dns-service = {
      description = "Allow DNS to local unbound listeners";
      wantedBy = [ "multi-user.target" ];
      wants = [ "nftables.service" ];
      after = [ "nftables.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        if ! ${pkgs.nftables}/bin/nft list chain inet router input | grep -q 'allow-dns-service'; then
          ${lib.concatStringsSep "\n          " nft.nftRules}
        fi

        if ! ${pkgs.nftables}/bin/nft list ruleset | grep -q 'allow-dns-service-egress'; then
          ${nft.dnsOutputScript}
        fi
      '';
    };
  }
