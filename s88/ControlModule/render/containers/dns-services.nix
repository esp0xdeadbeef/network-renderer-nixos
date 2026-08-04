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
      reproducibilityWarnings
      warningCodes
      localForwardZones
      requesterPolicies
      protectedReservationPublications
      dnsEgressPolicy
      validationAuthority
      infraHostTtl
      infraLameTtl
      ;

    controlledAuthority = validationAuthority != null;
    rootHintsFile =
      if controlledAuthority then
        pkgs.writeText "controlled-root-hints" (
          builtins.concatStringsSep "\n" (
            [ ". 60 IN NS ${validationAuthority.root.nameServer}" ]
            ++ map
              (address: "${validationAuthority.root.nameServer} 60 IN A ${address}")
              validationAuthority.root.ipv4
            ++ map
              (address: "${validationAuthority.root.nameServer} 60 IN AAAA ${address}")
              validationAuthority.root.ipv6
          )
          + "\n"
        )
      else
        null;

    requesterAccessControl = lib.concatMap
      (policy:
        map
          (cidr: "${cidr} ${policy.action}")
          (lib.filter builtins.isString (policy.sourcePrefixes or [ ])))
      requesterPolicies;
    accessControl = lib.unique ((map (cidr: "${cidr} allow") allowFrom) ++ requesterAccessControl);
    namespaceFallbackZoneSettings =
      map (decision: "${decision.namespace} static") namespaceFallbackDecisions;
    protectedReservationLocalZoneSettings =
      let
        conflicts = lib.filter
          (publication:
            builtins.any
              (zone: zone.name == publication.namespace && (zone.type or "static") != "static")
              localZones
            || builtins.any (zone: zone.name == publication.namespace) localForwardZones)
          protectedReservationPublications;
        forwardZones = map (publication: "${publication.namespace} static") protectedReservationPublications;
        # FS-560-HDS-010-SDS-010-SMS-050: when a protected publication includes
        # PTR records, the CPM also emits a reverseNamespace for the in-addr.arpa
        # or ip6.arpa zone so Unbound's local-data-ptr records are served from a
        # static authoritative zone.
        reverseZones = lib.filter (z: z != null) (map
          (publication:
            let rn = publication.reverseNamespace or null;
            in if builtins.isString rn && rn != "" then "${rn} static" else null)
          protectedReservationPublications);
        allZones = forwardZones ++ reverseZones;
      in
      if conflicts != [ ] then
        throw "diagnostic.protected-reservation-name-namespace-authority-conflict: NixOS DNS renderer rejected an overlapping local or forwarding namespace without logging address material"
      else
        allZones;
    localOnlyRootZoneSettings = lib.optional (recursionMode == "local-only") ". refuse";
    localZoneSettings =
      lib.unique (
        (map (zone: "${zone.name} ${zone.type or "static"}") localZones)
        ++ namespaceFallbackZoneSettings
        ++ protectedReservationLocalZoneSettings
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
    protectedReservationIncludes = map
      (publication: publication.configFile)
      protectedReservationPublications;
    protectedReservationGeneratorUnits = map
      (publication: publication.generatorUnit)
      protectedReservationPublications;
    nft = import ./dns-services/nft-rules.nix { inherit lib pkgs facts; };

    formatReproducibilityWarning = warning:
      let
        code = warning.code or "UNKNOWN";
        sourceLayer = warning.sourceLayer or "intent";
        enterprise = warning.enterprise or null;
        site = warning.site or null;
        requester = warning.requester or null;
        resolverService = warning.resolverService or null;
        relationId = warning.relationId or null;
        cpmMessage = warning.message or "";
        sitePath =
          if enterprise != null && site != null then
            "site \"${enterprise}/${site}\""
          else if site != null then
            "site \"${site}\""
          else
            null;
        relationPath =
          if requester != null && resolverService != null then
            "${requester} → ${resolverService}"
            + (if relationId != null then " (relation \"${relationId}\")" else "")
          else
            null;
        detailParts =
          lib.optional (sitePath != null) sitePath
          ++ lib.optional (relationPath != null) relationPath;
        detail = if detailParts != [ ] then " — ${lib.concatStringsSep "; " detailParts}" else "";
        body = if cpmMessage != "" then ": ${cpmMessage}" else "";
      in
      "network-renderer-nixos DNS reproducibility warning ${code} [${sourceLayer}]${body}${detail}; address material is intentionally omitted";
  in
  {
    warnings = map formatReproducibilityWarning reproducibilityWarnings;

    services.unbound = {
      enable = true;
      enableRootTrustAnchor = recursionMode == "iterative" && !controlledAuthority;
      settings = {
        server = {
          interface = listenAddresses;
          "access-control" = accessControl;
          "do-ip4" = true;
          "do-ip6" = true;
          "infra-host-ttl" = if infraHostTtl != null then infraHostTtl else 900;
        }
        // lib.optionalAttrs (infraLameTtl != null) {
          "infra-lame-ttl" = infraLameTtl;
        }
        // lib.optionalAttrs controlledAuthority {
          "root-hints" = "${rootHintsFile}";
          "domain-insecure" = [ "." ];
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
        // lib.optionalAttrs (protectedReservationIncludes != [ ]) {
          include = protectedReservationIncludes;
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
      wants = [ "network-online.target" "nft-allow-dns-service.service" ] ++ protectedReservationGeneratorUnits;
      after = [ "network-online.target" "nft-allow-dns-service.service" ] ++ protectedReservationGeneratorUnits;
      requires = protectedReservationGeneratorUnits;
    };

    systemd.network.networks = lib.optionalAttrs (dnsEgressPolicy != null) {
      "10-${dnsEgressPolicy.runtimeIfName}".routingPolicyRules = [
        {
          Family = "ipv4";
          FirewallMark = dnsEgressPolicy.firewallMark;
          Priority = dnsEgressPolicy.rulePriority;
          Table = dnsEgressPolicy.tableId;
        }
        {
          Family = "ipv6";
          FirewallMark = dnsEgressPolicy.firewallMark;
          Priority = dnsEgressPolicy.rulePriority;
          Table = dnsEgressPolicy.tableId;
        }
        {
          Family = "ipv4";
          User = "unbound";
          IPProtocol = "udp";
          DestinationPort = 53;
          Priority = dnsEgressPolicy.rulePriority;
          Table = dnsEgressPolicy.tableId;
        }
        {
          Family = "ipv4";
          User = "unbound";
          IPProtocol = "tcp";
          DestinationPort = 53;
          Priority = dnsEgressPolicy.rulePriority;
          Table = dnsEgressPolicy.tableId;
        }
        {
          Family = "ipv6";
          User = "unbound";
          IPProtocol = "udp";
          DestinationPort = 53;
          Priority = dnsEgressPolicy.rulePriority;
          Table = dnsEgressPolicy.tableId;
        }
        {
          Family = "ipv6";
          User = "unbound";
          IPProtocol = "tcp";
          DestinationPort = 53;
          Priority = dnsEgressPolicy.rulePriority;
          Table = dnsEgressPolicy.tableId;
        }
      ];
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

        ${nft.dnsPolicyRoutingScript}
      '';
    };
  }
