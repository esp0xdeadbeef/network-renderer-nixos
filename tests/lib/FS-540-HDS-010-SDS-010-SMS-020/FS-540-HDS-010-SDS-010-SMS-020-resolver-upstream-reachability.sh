#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# ============================================================================
# WHAT THIS ASSERTS, AND WHY IT CURRENTLY FAILS
# ============================================================================
#
# A resolver that forwards to an upstream must be able to REACH that upstream
# from its own process. "The route exists somewhere in the rendered config" is
# not that: a route is only usable by a socket if it is in the table that
# socket's traffic is looked up in.
#
# Two things decide that table:
#
#   * if the rendered config carries `User = "unbound"` policy rules, the
#     resolver's own queries are steered into the table those rules name;
#   * otherwise they fall to the main table (254).
#
# This case derives that table from the rendered rules, then requires:
#
#   1. every forwarded-to upstream address is covered by a route IN THAT TABLE;
#   2. that table carries NO default route (0.0.0.0/0, ::/0).
#
# (2) is an intent requirement, not tidiness: `clients-dns` may egress DNS only
# to its modelled resolver endpoints (`allowResolverToCoreDns`,
# `allowResolverToResolver ... unlock-dns`), and `deny-clients-dns-to-wan`
# forbids the WAN. A default route in the resolver's table is a road to the WAN
# and to every tenant sub-net, including the tang/unlock sub-net, which carries
# no DNS egress beyond its own resolver endpoint.
#
# MEASURED (2026-11-21), this fixture, before any fix:
#
#   10-transit0 routes: 10.2.0.3/32 -> table 1002 (only), and table 1002 also
#                       carries 0.0.0.0/0 and ::/0
#   10-transit0 rules:  no `User = unbound` rule at all
#
# so the access resolver's own queries are looked up in main (254), where its
# upstream has no route: measured on a booted cobalt HAT as
#
#   access-clients$ ip -4 route get 10.1.1.8
#     RTNETLINK answers: Network is unreachable
#   tenant-client$ dig @10.2.30.1 <name>
#     NXDomain from the access resolver, no packet leaving the node
#
# This is the same shape as the 2026-11-11 record ("unbound is routed into a
# table with no default"): the resolver listens, answers what it holds, and
# cannot forward, while every unit reports healthy.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
# shellcheck source=tests/lib/test-common.sh
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  "FS-540 resolver upstream reachability" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
  nix eval --impure --json --expr '
    let
      renderer = builtins.getFlake (toString (builtins.getEnv "REPO_ROOT"));
      system = builtins.currentSystem;
      trace = "FS-540-HDS-010-SDS-010-SMS-020";
      row = renderer.inputs.network-labs + "/GAMP/SMT/${trace}";
      cpm = renderer.inputs.network-control-plane-model.libBySystem.${system}.compileAndBuild {
        input = import (row + "/intent.nix");
        inventory = import (row + "/inventory-nixos.nix");
      };
      artifact = {
        kind = "network-control-plane-artifact";
        artifactIdentity = "${trace}-nixos-cpm";
        artifactDigest = builtins.hashString "sha256" (builtins.toJSON cpm.control_plane_model);
        inherit (cpm) control_plane_model;
      };
      bundle = renderer.inputs.network-realization-model.lib.realize {
        input = artifact;
        requestScope = {
          kind = "complete-artifact";
          identity = "${trace}-nixos";
        };
        rootLockIdentity = "network-renderer-nixos-flake-lock";
        producerRevision = renderer.inputs.network-realization-model.rev;
      };
      canonical = renderer.libBySystem.${system}.renderer.canonical;
      validated = canonical.validateInput { inherit bundle; };
      evaluated = renderer.inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          (canonical.hostModule {
            inherit bundle;
            hostName = "s-router-nixos";
          })
          ({ ... }: {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          })
        ];
      };
      cfg = evaluated.config;
      access = cfg.containers.access-dns.config;

      # The upstreams the access resolver actually forwards to. Read from the
      # rendered unbound config, not from the CPM: this case is about what the
      # renderer produced.
      forwardZones = access.services.unbound.settings."forward-zone" or [ ];
      upstreams = builtins.concatMap (zone: zone.forward-addr or [ ]) forwardZones;

      # Strip a port suffix if present; routes are keyed by address only.
      stripPort = entry:
        let m = builtins.match "([^@]+)(@.*)?" entry;
        in if m == null then entry else builtins.elemAt m 0;
      upstreamAddrs = map stripPort upstreams;

      networks = access.systemd.network.networks or { };
      networkList = map (name: networks.${name}) (builtins.attrNames networks);
      rulesOf = net: net.routingPolicyRules or [ ];
      routesOf = net: net.routes or [ ];
      allRules = builtins.concatMap rulesOf networkList;
      allRoutes = builtins.concatMap routesOf networkList;

      # The table the resolver own traffic is looked up in.
      lib = renderer.inputs.nixpkgs.lib;
      unboundTablesUnique = lib.unique (
        map (rule: rule.Table)
          (builtins.filter
            (rule: (rule.User or null) == "unbound" && builtins.isInt (rule.Table or null))
            allRules)
      );
      # No `unbound` rule => the resolver queries follow the main table.
      resolverTables =
        if unboundTablesUnique == [ ] then [ 254 ] else unboundTablesUnique;

      routeIsDefault = route:
        (route.Destination or null) == "0.0.0.0/0"
        || (route.Destination or null) == "::/0";

      # Routes the resolver can use: those whose Table is one of resolverTables.
      resolverRoutes = builtins.filter (
        route: builtins.elem (route.Table or 254) resolverTables
      ) allRoutes;

      # IPv4 containment, reusing the model ipam like the CPM case does.
      ipamCommon = import (
        renderer.inputs.network-control-plane-model.outPath
        + "/src/cpm/ControlModule/lib/ipam/common.nix"
      ) { lib = renderer.inputs.nixpkgs.lib; };
      ipamV4 = import (
        renderer.inputs.network-control-plane-model.outPath
        + "/src/cpm/ControlModule/lib/ipam/ipv4.nix"
      ) { common = ipamCommon; };

      covers = route: addr:
        let
          parsed = ipamCommon.splitCIDR (route.Destination or "");
          net = if parsed == null then null else ipamV4.parseIPv4 parsed.addr;
          target = ipamV4.parseIPv4 addr;
        in
        parsed != null
        && net != null
        && target != null
        && ipamV4.ipv4NetworkBaseInt {
          addrInt = ipamV4.ipv4ToInt target;
          inherit (parsed) prefixLen;
        } == ipamV4.ipv4NetworkBaseInt {
          addrInt = ipamV4.ipv4ToInt net;
          inherit (parsed) prefixLen;
        };

      isV4 = addr: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" addr != null;

      unreachable = builtins.filter (
        addr: isV4 addr && !(builtins.any (route: covers route addr) resolverRoutes)
      ) upstreamAddrs;

      reachableTableDefaults = builtins.filter routeIsDefault resolverRoutes;

      describeRoute = route: {
        destination = route.Destination or null;
        table = route.Table or 254;
        gateway = route.Gateway or null;
      };
    in
    {
      upstreamAddrs = upstreamAddrs;
      resolverTables = resolverTables;
      unboundRuleTables = unboundTablesUnique;
      unreachable = unreachable;
      defaultRoutesInResolverTables = map describeRoute reachableTableDefaults;
      routesInResolverTables = map describeRoute resolverRoutes;
      allRouteTables = lib.unique (map (route: route.Table or 254) allRoutes);
      ok = unreachable == [ ] && reachableTableDefaults == [ ];
    }
  '

if [[ -z "$(cat "${result_json}")" ]]; then
  fail "FS-540-HDS-010-SDS-010-SMS-020: the renderer evaluation produced no result"
fi

if [[ "$(_jq -r '.ok' "${result_json}")" == "true" ]]; then
  upstream_count="$(_jq -r '.upstreamAddrs | length' "${result_json}")"
  tables="$(_jq -r '.resolverTables | join(",")' "${result_json}")"
  pass "FS-540-HDS-010-SDS-010-SMS-020: ${upstream_count} resolved upstream address(es) reachable from the resolver's own table(s) ${tables}, no default route"
  exit 0
fi

{
  echo "FAIL FS-540-HDS-010-SDS-010-SMS-020: the access resolver cannot reach every upstream it forwards to."
  echo
  echo "  upstreams the resolver forwards to: $(_jq -r '.upstreamAddrs | join(", ")' "${result_json}")"
  echo "  table(s) its own queries are looked up in: $(_jq -r '.resolverTables | join(", ")' "${result_json}")"
  echo "    (derived from User=unbound rules: $(_jq -r 'if (.unboundRuleTables | length) == 0 then "none - so main (254)" else (.unboundRuleTables | join(", ")) end' "${result_json}") )"
  echo "  tables that actually carry routes: $(_jq -r '.allRouteTables | join(", ")' "${result_json}")"
  echo
  unreachable="$(_jq -r '.unreachable | join(", ")' "${result_json}")"
  if [[ -n "${unreachable}" ]]; then
    echo "  UNREACHABLE from the resolver's own table: ${unreachable}"
    echo "    There is no table selected for the resolver that has a route to it, so"
    echo "    unbound answers from its own authority and never forwards."
  fi
  defaults="$(_jq -r '.defaultRoutesInResolverTables | length' "${result_json}")"
  if ((defaults > 0)); then
    echo "  DEFAULT ROUTE IN THE RESOLVER'S TABLE:"
    _jq -r '.defaultRoutesInResolverTables[] | "    \(.destination) via \(.gateway // "-") table \(.table)"' "${result_json}"
    echo "    A default route is not a modelled path to one upstream: it is a road to"
    echo "    the WAN and every tenant sub-net. deny-clients-dns-to-wan forbids the"
    echo "    WAN, and the tang/unlock sub-net carries no DNS egress beyond its own"
    echo "    resolver endpoint (allowResolverToResolver clients-dns -> unlock-dns)."
  fi
  echo
  echo "  The fix is NOT to steer the resolver into a table that has a default;"
  echo "  that satisfies availability and breaks the intent. It is to put a host"
  echo "  route to each modelled upstream into the table the resolver's traffic"
  echo "  already uses."
} >&2
exit 1
