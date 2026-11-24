#!/usr/bin/env bash
# GAMP-ID: FS-560-HDS-010-SDS-010-SMS-050
# GAMP-ID: FS-800-HDS-030-SDS-020-SMS-020
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-075
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_RENDERER_NIXOS_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

REPO_ROOT="${repo_root}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    diagnose = controlPlane:
      import (repoRoot + "/s88/ControlModule/render/model-contract-diagnostics.nix") {
        inherit lib controlPlane;
        hostName = "test-host";
      };
    ipv6Pd = {
      mode = "dhcpv6-pd";
      defaultRoute = true;
      iaid = 7;
      prefixDelegationRequestId = 11;
      duidMode = "persistent";
      resolverMode = "disabled";
      ipv4Mode = "disabled";
      routerSolicitation = false;
      fallbackPolicy = "none";
    };
    publication = {
      namespace = "lan.";
      ownerScope = "tenant";
      requesterScopes = [ "tenant" ];
      recordClasses = [ "A" "PTR" ];
      fallbackBehavior = "local-only";
      publicationDenialDiagnostic = "deny";
      source = "protected-reservation-set";
      sourceFamily = "ipv4";
    };
    relation4 = {
      id = "public-v4";
      trafficType = "service";
      from = { kind = "external"; uplinks = [ "wan" ]; };
      to = { kind = "service"; name = "protected-service"; };
      publicIngressTupleAuthority = {
        targetService = "protected-service";
        translationMode = "napt";
      };
    };
    relation6 = relation4 // {
      id = "public-v6";
      publicIngressTupleAuthority = relation4.publicIngressTupleAuthority // {
        family = "ipv6";
        translationMode = "none";
      };
    };
    mkControlPlane = complete: {
      deploymentHosts.test-host = { };
      control_plane_model.data.enterprise.site = {
        communicationContract.trafficTypes = [{
          name = "service";
          match = [{ proto = "udp"; family = "any"; }];
        }];
        relations = [ relation4 ] ++ lib.optional complete relation6;
        routedPrefixes.tenant = [{ family = "ipv6"; allocation = "runtime"; }];
        dns.warnings = lib.optional (!complete) {
          traceId = "FS-560-HDS-010-SDS-020-SMS-010";
          code = "DNS_LOCAL_SHARING_INTENT_MISSING";
          sourceLayer = "intent";
          message = "Missing directional namespace authority";
        };
        runtimeTargets = {
          core = {
            deploymentHost = "test-host";
            services.pppoe.client = {
              interface = "wan";
              mtu = 1492;
            } // lib.optionalAttrs complete { ipv6 = ipv6Pd; };
          };
          access = {
            deploymentHost = "test-host";
            advertisements.dhcp4 = [{
              reservationSource = {
                sourceClass = "protected";
              } // lib.optionalAttrs complete { namePublication = publication; };
            }];
          };
        };
      };
    };
    incomplete = diagnose (mkControlPlane false);
    complete = diagnose (mkControlPlane true);
    dnsAuthority = import (repoRoot + "/s88/ControlModule/render/containers/dns-services/authority.nix") {
      inherit lib;
      dnsService.reproducibilityWarnings = [{
        traceId = "FS-560-HDS-010-SDS-020-SMS-010";
        code = "DNS_LOCAL_SHARING_INTENT_MISSING";
        sourceLayer = "intent";
        message = "Missing directional namespace authority";
      }];
    };
    messages = builtins.concatStringsSep "\n" incomplete.warnings;
    require = condition: message: if condition then true else throw message;
  in
  if
    require (builtins.length incomplete.warnings == 4) "incomplete model did not produce four owned warnings"
    && require (lib.hasInfix "DNS_LOCAL_SHARING_INTENT_MISSING" messages) "CPM DNS warning was not projected"
    && require (lib.hasInfix "PROTECTED_RESERVATION_NAME_PUBLICATION_MISSING" messages) "reservation publication gap did not warn"
    && require (lib.hasInfix "PPPOE_IPV6_PD_CONTRACT_MISSING" messages) "PD inventory gap did not warn"
    && require (lib.hasInfix "PUBLIC_INGRESS_IPV6_AUTHORITY_MISSING" messages) "IPv6 public ingress intent gap did not warn"
    && require (dnsAuthority.warningCodes == [ "DNS_LOCAL_SHARING_INTENT_MISSING" ]) "intent warning was escalated to a DNS renderer failure"
    && require (complete.warnings == [ ]) "complete model produced compatibility warnings"
  then "ok" else throw "unreachable"
' >/dev/null

echo "PASS renderer model-contract diagnostics"
