#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

nix_eval_json_or_fail "public-ingress-module" "$result_json" "$stderr_file" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure \
  --expr '
let
  flake = builtins.getFlake ("path:" + toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  module = import ./s88/ControlModule/module/public-ingress.nix {
    inherit lib pkgs;
    hostName = "hetzner";
    runtimeFacts.publicIngress = {
      snatSourceCidr4 = "172.31.254.0/24";
      services.acme.dmz-site.dmz-nebula = {
        publicIPv4SecretPath = "/run/secrets/lighthouse-public-ipv4";
        assignToBridge = true;
        gateway4 = "172.31.254.3";
      };
      runtimeForwards = [
        {
          publicIPv4SecretPath = "/run/secrets/core-public-ipv4";
          targetIPv4 = "172.31.254.2";
          protocols = [ "tcp" "udp" ];
          protectServiceDports = false;
          exceptTcpDports = [ 22 ];
          inputDports = [ 4242 ];
          containerInterface = {
            container = "c-router-nebula-core";
            name = "portforward";
            hostBridge = "br-wan";
            localAddress = "172.31.254.2/24";
            gateway4 = "172.31.254.1";
          };
        }
      ];
    };
    inventory = {
      deployment.hosts.hetzner = {
        wanUplink = "wan";
        uplinks.wan.bridge = "br-wan";
      };
    };
    controlPlane.control_plane_model.data.acme.dmz-site = {
      relations = [
        {
          action = "allow";
          from = {
            kind = "external";
            name = "wan";
          };
          to = {
            kind = "service";
            name = "dmz-nebula";
          };
          trafficType = "nebula";
        }
      ];
      communicationContract.trafficTypes = [
        {
          name = "nebula";
          match = [
            {
              proto = "udp";
              family = "any";
              dports = [ 4242 ];
            }
          ];
        }
      ];
      policy.endpointBindings.services.dmz-nebula = {
        providers = [ "c-router-lighthouse" ];
        trafficType = "nebula";
      };
      services = [
        {
          name = "dmz-nebula";
          providers = [ "c-router-lighthouse" ];
          providerEndpoints = [
            {
              name = "c-router-lighthouse";
              ipv4 = [ "10.90.10.100" ];
              ipv6 = [ "fd42:dead:cafe:10::100" ];
            }
          ];
          trafficType = "nebula";
        }
      ];
    };
  };
  rules = module.networking.nftables.ruleset;
  checks = {
    ipv4ForwardingEnabled = module.boot.kernel.sysctl."net.ipv4.ip_forward".content == true;
    serviceDnatFromCpmRelation =
      lib.hasInfix "ip daddr @s88_public_service_acme_dmz_site_dmz_nebula meta l4proto udp udp dport 4242 dnat to 10.90.10.100" rules;
    serviceDnatSupportsBridgeHairpin =
      !(lib.hasInfix "iifname != \"br-wan\" ip daddr @s88_public_service_acme_dmz_site_dmz_nebula meta l4proto udp udp dport 4242 dnat to 10.90.10.100" rules);
    serviceHairpinForwardIsAllowed =
      lib.hasInfix "iifname \"br-wan\" oifname \"br-wan\" ip daddr 10.90.10.100 meta l4proto udp udp dport 4242 accept comment \"s88-public-service-dmz-nebula\"" rules;
    serviceHairpinDoesNotSnat =
      !(lib.hasInfix "s88-host-public-ingress-hairpin-snat" rules);
    serviceTargetRouteUsesRuntimeGateway =
      builtins.elem
        { Destination = "10.90.10.100/32"; Gateway = "172.31.254.3"; }
        module.systemd.network.networks."30-br-wan".routes;
    runtimeForwardKeepsHostSsh =
      lib.hasInfix "ip daddr @s88_public_runtime_0 meta l4proto tcp tcp dport != { 22 } dnat to 172.31.254.2" rules;
    runtimeForwardDoesNotStealServiceUdp =
      lib.hasInfix "ip daddr @s88_public_runtime_0 meta l4proto udp dnat to 172.31.254.2" rules;
    publicIngressDefinesRuntimeSets =
      lib.hasInfix "set s88_public_service_acme_dmz_site_dmz_nebula" rules
      && lib.hasInfix "set s88_public_runtime_0" rules;
    publicIngressLoadsRuntimeSetsFromSecrets =
      lib.hasInfix "load_public_ipv4 \"s88_public_service_acme_dmz_site_dmz_nebula\" \"/run/secrets/lighthouse-public-ipv4\" 1" module.systemd.services.s88-host-public-ingress-runtime-addresses.script
      && lib.hasInfix "load_public_ipv4 \"s88_public_runtime_0\" \"/run/secrets/core-public-ipv4\" 0" module.systemd.services.s88-host-public-ingress-runtime-addresses.script;
    publicIngressAssignsFloatingServiceAddress =
      lib.hasInfix "ip addr replace \"$value/32\" dev \"br-wan\"" module.systemd.services.s88-host-public-ingress-runtime-addresses.script;
    snatUsesRuntimeCidr =
      lib.hasInfix "ip saddr 172.31.254.0/24 oifname != \"br-wan\" masquerade" rules;
    forwardPolicyDropsByDefault =
      lib.hasInfix "type filter hook forward priority filter; policy drop;" rules;
    runtimeForwardAddsContainerVeth =
      module.containers.c-router-nebula-core.extraVeths.portforward.hostBridge == "br-wan"
      && module.containers.c-router-nebula-core.extraVeths.portforward.localAddress == "172.31.254.2/24";
    runtimeForwardAddsContainerRoute =
      let
        containerModule = module.containers.c-router-nebula-core.config { inherit lib; };
        network = containerModule.systemd.network.networks."10-portforward".content;
        routes = network.routes;
      in
      builtins.elem { Gateway = "172.31.254.1"; Metric = 5000; } routes
      && builtins.elem { Destination = "0.0.0.0/0"; Gateway = "172.31.254.1"; Table = 2200; } routes;
    runtimeForwardAddsSourcePolicy =
      let
        containerModule = module.containers.c-router-nebula-core.config { inherit lib; };
        network = containerModule.systemd.network.networks."10-portforward".content;
      in
      builtins.elem { Family = "ipv4"; From = "172.31.254.2"; Priority = 9000; Table = 2200; } network.routingPolicyRules;
    runtimeForwardOpensInputPort =
      let
        containerModule = module.containers.c-router-nebula-core.config { inherit lib; };
      in
      lib.hasInfix "insert rule inet router input iifname \"portforward\" meta l4proto udp udp dport 4242 accept" containerModule.networking.nftables.ruleset.content
      && lib.hasInfix "insert rule inet router input iifname \"portforward\" meta l4proto tcp tcp dport 4242 accept" containerModule.networking.nftables.ruleset.content;
  };
in
{
  ok = builtins.all (value: value == true) (builtins.attrValues checks);
  failed = lib.mapAttrsToList (name: _value: name) (lib.filterAttrs (_name: value: value != true) checks);
  inherit checks rules;
}
'

assert_json_checks_ok "public-ingress-module" "$result_json"
echo "PASS public-ingress-module"
