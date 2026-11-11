#!/usr/bin/env bash
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
#
# `multipath-merge.nix` groups routes by (Table, Destination, Metric). A group of
# DEFAULT routes that carried two or more distinct gateways used to be replaced
# with `[ ]`, deleting every route in it.
#
# Those are not equal-cost paths to a single next hop. They are the same
# `0.0.0.0/0` contributed by DIFFERENT source interfaces, each toward its own
# lane peer, so the correct behaviour is one default per source -- not an ECMP
# merge and certainly not deletion.
#
# Measured on the cobalt HAT, 2026-11-11, before the fix:
#
#   model     clients lane 63 routes / 18 x 0.0.0.0/0 over 8 gateways
#   merge     >= 2 gateways in one group -> `[ ]`, every default gone
#   networkd  10-pdspaac: 248 routes, 0 defaults
#   live      tenant traceroute 1.1.1.1 -> 10.1.0.1 !N
#
# The unlock lane appeared to work only because its defaults split across tables
# 1008 and 1016, leaving fewer than two gateways per group so the arm never
# fired -- which is why the defect looked lane-specific.
#
# After the fix the same tenant reaches the internet:
#   1 10.2.30.1 access-clients  2 10.1.0.1 downstream-selector
#   3 10.1.0.25 policy          4 10.1.0.41 upstream-selector
#   5 10.1.0.16 core            6 192.0.2.1 the ISP   0% loss
#
# This case asserts the module contract directly, so it does not need a VM.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

nix eval --impure --no-warn-dirty --json --expr '
let
  flake = builtins.getFlake (toString '"$repo_root"');
  lib = flake.inputs.nixpkgs.lib;
  mergeModule = import (toString '"$repo_root"' + "/s88/ControlModule/render/container-networks/policy-routing/multipath-merge.nix");
  merge = second: mergeModule ({ inherit lib; renderedInterfaceNames = { }; } // second);

  mkDefault = table: metric: gateway: {
    Destination = "0.0.0.0/0";
    Gateway = gateway;
    GatewayOnLink = true;
    Metric = metric;
    Table = table;
  };
  mkRoute = dst: gateway: table: {
    Destination = dst;
    Gateway = gateway;
    GatewayOnLink = true;
    Metric = 50;
    Table = table;
  };

  # The shape that broke: three source interfaces each contributing a default
  # toward their own peer, all sharing one (table, destination, metric) key.
  multiGatewayDefaults = merge {
    routesByInterface = {
      a = [ (mkDefault 1009 50 "10.1.0.25") ];
      b = [ (mkDefault 1009 50 "10.1.0.27") ];
      c = [ (mkDefault 1009 50 "10.1.0.29") ];
    };
  };

  # One source only: nothing to merge, the route must survive untouched.
  singleDefault = merge {
    routesByInterface = {
      a = [ (mkDefault 1009 50 "10.1.0.25") ];
    };
  };

  # Same gateway from two sources is a genuine ECMP pair, not per-lane peers.
  sameGateway = merge {
    routesByInterface = {
      a = [ (mkDefault 1009 50 "10.1.0.25") ];
      b = [ (mkDefault 1009 50 "10.1.0.25") ];
    };
  };

  # Non-default routes are never touched by the merge arm.
  nonDefaults = merge {
    routesByInterface = {
      a = [ (mkRoute "10.1.0.16/31" "10.1.0.25" 1009) ];
      b = [ (mkRoute "10.1.0.18/31" "10.1.0.27" 1009) ];
    };
  };

  # Neither foldl nor foldl-with-apostrophe can be written here: only the
  # apostrophe form exists in builtins, and an apostrophe cannot appear inside
  # the single-quoted shell string this Nix expression lives in. Sum the lengths
  # directly instead.
  sum = xs: if xs == [ ] then 0 else (builtins.head xs) + sum (builtins.tail xs);
  listsOf = m: map (n: m.${n}) (builtins.attrNames m);
  total = m: sum (map builtins.length (listsOf m));

  # Every surviving default must still name its own source interface, i.e. the
  # per-source association is preserved and nothing was dropped.
  sourcesWithDefaults = m:
    builtins.filter (name: m.${name} != [ ]) (builtins.attrNames m);
in
  {
    # The regression: three per-source defaults must survive, not vanish.
    multiGatewayKept = total multiGatewayDefaults == 3;
    multiGatewaySources = sourcesWithDefaults multiGatewayDefaults;
    # A lone default is untouched.
    singleKept = total singleDefault == 1;
    # Identical gateways still collapse or keep, but must never be deleted.
    sameGatewayNotDeleted = total sameGateway >= 1;
    # Non-defaults always survive.
    nonDefaultsKept = total nonDefaults == 2;
  }
' > /tmp/fs370-multipath-result.json

jq -e '
  .multiGatewayKept == true
  and .singleKept == true
  and .sameGatewayNotDeleted == true
  and .nonDefaultsKept == true
  and (.multiGatewaySources | length) == 3
' /tmp/fs370-multipath-result.json >/dev/null || {
  echo "FAIL multipath-merge-defaults: defaults that share a key but not a gateway must be kept, one per source interface" >&2
  cat /tmp/fs370-multipath-result.json >&2
  exit 1
}

echo "PASS multipath-merge-defaults"
