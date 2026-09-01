{
  lib,
  pkgs,
  renderedModel,
  forwardingIntent ? { },
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
      registeredUpstreams
      registeredUpstreams4
      registeredUpstreams6
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
      strictEgress
      dnsFile
      ;

    controlledAuthority = validationAuthority != null;
    rootHintsFile =
      if controlledAuthority then
        pkgs.writeText "controlled-root-hints" (
          builtins.concatStringsSep "\n" (
            [ ". 60 IN NS ${validationAuthority.root.nameServer}" ]
            ++ map (
              address: "${validationAuthority.root.nameServer} 60 IN A ${address}"
            ) validationAuthority.root.ipv4
            ++ map (
              address: "${validationAuthority.root.nameServer} 60 IN AAAA ${address}"
            ) validationAuthority.root.ipv6
          )
          + "\n"
        )
      else
        null;

    dnsFileForwarderMaterializer = pkgs.writeShellScriptBin "dns-file-forwarder-materializer" ''
      set -euo pipefail
      dns_file="$1"
      out_file="$2"
      {
        echo 'forward-zone:'
        echo '  name: "."'
        tr ',' '\n' < "$dns_file" \
          | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
          | grep -v '^$' \
          | while read -r addr; do
              echo "  forward-addr: $addr"
            done
      } > "$out_file"
    '';

    dnsEgressRoutingMaterializer = pkgs.writeShellScriptBin "dns-egress-routing-materializer" ''
      set -euo pipefail
      table_id="$1"
      fwmark="$2"
      priority="$3"
      ifname="$4"
      ip rule add priority "$priority" fwmark "$fwmark" lookup "$table_id" 2>/dev/null || true
      ip route replace default dev "$ifname" table "$table_id" 2>/dev/null || true
      ip -6 route replace default dev "$ifname" table "$table_id" 2>/dev/null || true
    '';

    requesterAccessControl = lib.concatMap (
      policy:
      map (cidr: "${cidr} ${policy.action}") (lib.filter builtins.isString (policy.sourcePrefixes or [ ]))
    ) requesterPolicies;
    accessControl = lib.unique ((map (cidr: "${cidr} allow") allowFrom) ++ requesterAccessControl);
    namespaceFallbackZoneSettings = map (
      decision: "${decision.namespace} static"
    ) namespaceFallbackDecisions;
    protectedReservationLocalZoneSettings =
      let
        conflicts = lib.filter (
          publication:
          builtins.any (
            zone: zone.name == publication.namespace && (zone.type or "static") != "static"
          ) localZones
          || builtins.any (zone: zone.name == publication.namespace) localForwardZones
        ) protectedReservationPublications;
        forwardZones = map (
          publication: "${publication.namespace} static"
        ) protectedReservationPublications;

        reverseZones = lib.filter (z: z != null) (
          map (
            publication:
            let
              rn = publication.reverseNamespace or null;
            in
            if builtins.isString rn && rn != "" then "${rn} static" else null
          ) protectedReservationPublications
        );
        allZones = forwardZones ++ reverseZones;
      in
      if conflicts != [ ] then
        throw "diagnostic.protected-reservation-name-namespace-authority-conflict: NixOS DNS renderer rejected an overlapping local or forwarding namespace without logging address material"
      else
        allZones;
    localOnlyRootZoneSettings = lib.optional (recursionMode == "local-only") ". refuse";
    localZoneSettings = lib.unique (
      (map (zone: "${zone.name} ${zone.type or "static"}") localZones)
      ++ namespaceFallbackZoneSettings
      ++ protectedReservationLocalZoneSettings
      ++ localOnlyRootZoneSettings
    );
    localForwardZoneSettings = map (zone: {
      name = zone.name;
      "forward-addr" = zone.forwardTo;
      "forward-first" = zone.forwardFirst;
    }) localForwardZones;
    localDataSettings = lib.concatMap (
      record:
      let
        name = record.name;
        a = if builtins.isList (record.a or null) then lib.filter builtins.isString record.a else [ ];
        aaaa =
          if builtins.isList (record.aaaa or null) then lib.filter builtins.isString record.aaaa else [ ];
      in
      (map (addr: "\"${name} IN A ${addr}\"") a) ++ (map (addr: "\"${name} IN AAAA ${addr}\"") aaaa)
    ) localRecords;

    localDataPtrSettings = lib.concatMap (
      record:
      let
        name = record.name;
        a = if builtins.isList (record.a or null) then lib.filter builtins.isString record.a else [ ];
        aaaa =
          if builtins.isList (record.aaaa or null) then lib.filter builtins.isString record.aaaa else [ ];
      in
      (map (addr: "\"${addr} ${name}\"") a) ++ (map (addr: "\"${addr} ${name}\"") aaaa)
    ) localRecords;
    protectedReservationIncludes = map (
      publication: publication.configFile
    ) protectedReservationPublications;
    protectedReservationGeneratorUnits = map (
      publication: publication.generatorUnit
    ) protectedReservationPublications;
    nft = import ./dns-services/nft-rules.nix { inherit lib pkgs facts; };

    registeredUpstreamMaterializer = pkgs.writeShellApplication {
      name = "dns-registered-upstream-materializer";
      runtimeInputs = [
        pkgs.nftables
        pkgs.coreutils
      ];
      text = ''
        set -euo pipefail
        out=/run/unbound/registered-upstream.conf
        tmp="$(mktemp)"
        v4file="$(mktemp)"
        v6file="$(mktemp)"
        trap 'rm -f "$tmp" "$v4file" "$v6file"' EXIT
        printf 'forward-zone:\n  name: "."\n' > "$tmp"
        for sourceFile in "$@"; do
          while IFS= read -r addr; do
            addr="''${addr%%#*}"
            addr="''${addr//[[:space:]]/}"
            [ -n "$addr" ] || continue
            case "$addr" in
              *:*) printf '%s\n' "$addr" >> "$v6file" ;;
              *)   printf '%s\n' "$addr" >> "$v4file" ;;
            esac
            printf '  forward-addr: %s\n' "$addr" >> "$tmp"
          done < "$sourceFile"
        done
        install -m 0644 "$tmp" "$out"
        if [ -s "$v4file" ]; then
          ${pkgs.nftables}/bin/nft flush set inet router s88_dns_upstream4
          ${pkgs.nftables}/bin/nft add element inet router s88_dns_upstream4 "{ $(paste -sd, "$v4file") }"
        fi
        if [ -s "$v6file" ]; then
          ${pkgs.nftables}/bin/nft flush set inet router s88_dns_upstream6
          ${pkgs.nftables}/bin/nft add element inet router s88_dns_upstream6 "{ $(paste -sd, "$v6file") }"
        fi
      '';
    };

    registeredUpstreamSourceFiles = lib.concatStringsSep " " (
      map (entry: lib.escapeShellArg entry.sourceFile) registeredUpstreams
    );

    formatReproducibilityWarning =
      warning:
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
          lib.optional (sitePath != null) sitePath ++ lib.optional (relationPath != null) relationPath;
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
          "infra-host-ttl" = if infraHostTtl != null then infraHostTtl else 60;

          "msg-cache-size" = "128m";
          "rrset-cache-size" = "256m";
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
        // lib.optionalAttrs (localDataPtrSettings != [ ]) {
          "local-data-ptr" = localDataPtrSettings;
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
      }
      // lib.optionalAttrs (registeredUpstreams != [ ]) {
        include = [ "/run/unbound/registered-upstream.conf" ];
      }
      // lib.optionalAttrs (dnsFile != null) {
        include = [ "/run/unbound/provider-forwarders.conf" ];
      };
    };

    systemd.services.unbound = {
      wants = [
        "network-online.target"
        "nft-allow-dns-service.service"
      ]
      ++ protectedReservationGeneratorUnits
      ++ (lib.optional (dnsFile != null) "dns-provider-forwarders.service")
      ++ (lib.optional (dnsEgressPolicy != null) "dns-egress-routing.service");
      after = [
        "network-online.target"
        "nft-allow-dns-service.service"
      ]
      ++ protectedReservationGeneratorUnits
      ++ (lib.optional (dnsFile != null) "dns-provider-forwarders.service")
      ++ (lib.optional (dnsEgressPolicy != null) "dns-egress-routing.service");
      requires = protectedReservationGeneratorUnits;
    };

    systemd.services.dns-registered-upstream = lib.optionalAttrs (registeredUpstreams != [ ]) {
      description = "Materialize registered DNS upstreams into unbound and nftables";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "nft-allow-dns-service.service"
      ];
      after = [
        "network-online.target"
        "nft-allow-dns-service.service"
      ];
      before = [ "unbound.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${registeredUpstreamMaterializer}/bin/dns-registered-upstream-materializer ${registeredUpstreamSourceFiles}";
      };
    };

    systemd.services.dns-provider-forwarders = lib.optionalAttrs (dnsFile != null) {
      description = "Materialize provider DNS forwarders into unbound";
      wantedBy = [ "multi-user.target" ];
      before = [ "unbound.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "unbound";
        ExecStart = "${dnsFileForwarderMaterializer}/bin/dns-file-forwarder-materializer ${dnsFile} /run/unbound/provider-forwarders.conf";
      };
    };

    systemd.services.dns-egress-routing = lib.optionalAttrs (dnsEgressPolicy != null) {
      description = "Materialize DNS runtime-origin egress policy routing";
      wantedBy = [ "multi-user.target" ];
      before = [ "unbound.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${dnsEgressRoutingMaterializer}/bin/dns-egress-routing-materializer ${toString dnsEgressPolicy.tableId} ${toString dnsEgressPolicy.firewallMark} ${toString dnsEgressPolicy.rulePriority} ${dnsEgressPolicy.runtimeIfName}";
      };
    };

    systemd.network.networks = lib.optionalAttrs (dnsEgressPolicy != null) {
      "10-${dnsEgressPolicy.runtimeIfName}" = {
        matchConfig.Name = dnsEgressPolicy.runtimeIfName;
        routingPolicyRules = [
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
    };

    systemd.services.dns-upstream-health = {
      description = "Restart unbound when the DNS chain recovers";
      wantedBy = [ "multi-user.target" ];
      after = [ "unbound.service" ];
      path = with pkgs; [
        coreutils
        dnsutils
        gnugrep
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "dns-upstream-health" ''
          set -euo pipefail
          flag=/run/unbound-upstream-down
          dig=${pkgs.dnsutils}/bin/dig

          up=1



          if ! "$dig" +short +time=2 +tries=1 localhost A @127.0.0.1 | ${pkgs.gnugrep}/bin/grep -q .; then
            up=0
          fi





          if [ "${if forwarders != [ ] then "1" else "0"}" = "1" ]; then
            probe="health-$(cat /proc/sys/kernel/random/uuid).invalid"
            if "$dig" +time=3 +tries=1 "$probe" @127.0.0.1 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q SERVFAIL; then
              up=0
            fi
          fi

          if [ "$up" = 0 ]; then
            : > "$flag"
            exit 0
          fi

          if [ -f "$flag" ]; then
            rm -f "$flag"
            systemctl restart unbound
            echo "[dns-upstream-health] DNS chain recovered; restarted unbound to drop stale failure cache" >&2
          fi
        '';
      };
    };

    systemd.timers.dns-upstream-health = {
      description = "Periodic DNS chain health check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "45s";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
        Unit = "dns-upstream-health.service";
      };
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

        ${lib.concatStringsSep "\n        " nft.dnsUpstreamSetDefinitions}

        if ! ${pkgs.nftables}/bin/nft list ruleset | grep -q 'allow-dns-service-egress'; then
          ${nft.dnsOutputScript}
        fi

        ${nft.dnsPolicyRoutingScript}
      '';
    };
  }
