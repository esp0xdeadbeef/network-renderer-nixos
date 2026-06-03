#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-002
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-004
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-CMC-001-002
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-CMC-001-003
# GAMP-ID: USR-MODEL-001-FS-001-HDS-001-SDS-001-003-SMS-001-CMC-001-004
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
      renderedModel = {
        runtimeTarget.services.dns = {
          listen = [ "10.20.0.1" "fd00:20::1" ];
          allowFrom = [ "10.20.0.0/24" "fd00:20::/64" ];
          forwarders = [ "1.1.1.1" "2606:4700:4700::1111" ];
          localZones = [
            {
              name = "printer.";
              type = "static";
            }
            {
              name = "home-users.";
            }
          ];
          localRecords = [
            {
              name = "test-machine-01.printer.";
              a = [ "10.20.0.10" ];
              aaaa = [ "fd00:20::10" ];
            }
            {
              name = "tv-01.home-users.";
              a = [ "10.20.0.20" ];
            }
          ];
          deniedResolverCidrs = [ "1.1.1.1/32" "2606:4700:4700::1111/128" ];
        };
        interfaces.transit = {
          sourceKind = "p2p";
          addresses = [ "10.99.0.2/31" "fd00:99::2/127" ];
          containerInterfaceName = "transit";
        };
      };
      rendered =
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs renderedModel;
        };
      renderedWithExplicitOutgoing =
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs;
          renderedModel =
            renderedModel
            // {
              runtimeTarget.services.dns =
                renderedModel.runtimeTarget.services.dns
                // {
                  outgoingInterfaces = [ "10.99.0.2" ];
                };
            };
        };
      renderedWithRoleOutgoing =
        import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs;
          renderedModel =
            renderedModel
            // {
              runtimeTarget.services.dns =
                renderedModel.runtimeTarget.services.dns
                // {
                  roles.recursion.outgoingInterfaces = [ "10.99.0.3" ];
                  outgoingInterfaces = [ "10.99.0.2" ];
                };
            };
        };
      server = rendered.services.unbound.settings.server;
      explicitServer = renderedWithExplicitOutgoing.services.unbound.settings.server;
      roleServer = renderedWithRoleOutgoing.services.unbound.settings.server;
      unboundService = rendered.systemd.services.unbound;
      unboundRootAnchor = rendered.services.unbound.enableRootTrustAnchor or true;
      nftScript = renderedWithExplicitOutgoing.systemd.services.nft-allow-dns-service.script;
      roleNftScript = renderedWithRoleOutgoing.systemd.services.nft-allow-dns-service.script;
      localZones = server."local-zone" or [ ];
      localData = server."local-data" or [ ];
      ok =
        builtins.elem "printer. static" localZones
        && builtins.elem "home-users. static" localZones
        && builtins.elem "\"test-machine-01.printer. IN A 10.20.0.10\"" localData
        && builtins.elem "\"test-machine-01.printer. IN AAAA fd00:20::10\"" localData
        && builtins.elem "\"tv-01.home-users. IN A 10.20.0.20\"" localData
        && !(server ? "outgoing-interface")
        && (explicitServer."outgoing-interface" or [ ]) == [ "10.99.0.2" ]
        && (roleServer."outgoing-interface" or [ ]) == [ "10.99.0.3" ]
        && lib.hasInfix "ip saddr 10.99.0.3 ip daddr 1.1.1.1 udp dport 53 accept comment \"allow-dns-service-egress\"" roleNftScript
        && !(lib.hasInfix "ip saddr 10.99.0.2 ip daddr 1.1.1.1 udp dport 53 accept comment \"allow-dns-service-egress\"" roleNftScript)
        && lib.hasInfix "ip saddr 10.99.0.2 ip daddr 1.1.1.1 udp dport 53 accept comment \"allow-dns-service-egress\"" nftScript
        && !(lib.hasInfix "ip saddr 10.53.0.1 ip daddr 1.1.1.1 udp dport 53 accept comment \"allow-dns-service-egress\"" nftScript)
        && lib.hasInfix "deny-public-dns-output-leak" nftScript
        && server."infra-host-ttl" == 1
        && server."infra-lame-ttl" == 1
        && unboundRootAnchor == false
        && builtins.elem "network-online.target" unboundService.after
        && builtins.elem "network-online.target" unboundService.wants;
    in
      if ok then true else throw "dns-local-records failed: rendered DNS service must not add a default outgoing-interface, explicit outgoingInterfaces must still override that default, and hardware boot must not depend on root-anchor refresh"
  ' >/dev/null || {
    echo "FAIL dns-local-records" >&2
    exit 1
  }

echo "PASS dns-local-records"
