#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-320-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# FS "Site Fabric Traffic Flow": an access space reaches the policy point only
# through the modelled route on its attach target. FS:1304 forbids the host from
# supplying default routes to endpoint containers, so the container render must
# carry the attach-target routes itself.
#
#   P1  a route modelled only on the attach target appears on the container
#       interface (regression: 2026-11-10, pdspaac had 248 routes / 0 defaults
#       while the host model received them)
#   P2  a route present on both sides is emitted once

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

module="${repo_root}/s88/ControlModule/mapping/container-runtime/interfaces/normalize.nix"

common="
let
  lib = (import <nixpkgs> { }).lib;
  naming = {
    validInterfaceName = n: builtins.isString n && n != \"\";
    semanticBaseInterfaceName = n: n;
    semanticHostVethBaseName = { containerName, desiredInterfaceName, adapterName ? null }: \"veth-\" + desiredInterfaceName;
    assignUniqueContainerInterfaceNames = x: x;
    assignUniqueHostVethNames = x: x;
  };
  attach = {
    sourceKindForInterface = _: \"accepted-ingress\";
    attachTargetForInterface = { unitName, ifName, iface }: iface.attachTarget or null;
    interfaceNameFromAttachTarget = _: null;
    interfaceNameFromUpstream = _: null;
  };
  normalize = import \"${module}\" {
    inherit lib naming attach;
    lookup.sortedAttrNames = a: builtins.sort builtins.lessThan (builtins.attrNames a);
  };
in
"

nix_eval_true_or_fail "FS-320-HDS-010-SDS-010-SMS-030 P1 attach-target route reaches the container interface" \
  env REPO_ROOT="${repo_root}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --expr "${common}"'
    let
      interfaces = {
        pdspaac = {
          renderedIfName = "pdspaac";
          addresses = [ "10.1.0.22/31" ];
          routes = [ { dst = "10.1.0.0/31"; via = "10.1.0.23"; table = 1001; metric = 50; } ];
          attachTarget = {
            renderedHostBridgeName = null;
            routes = [ { dst = "0.0.0.0/0"; via = "10.1.0.23"; table = 1001; metric = 50; } ];
          };
        };
      };
      out = normalize.normalizedInterfacesForUnit {
        unitName = "downstream-selector"; containerName = "downstream-selector"; inherit interfaces;
      };
      routes = out.pdspaac.routes;
      defaults = builtins.filter (r: (r.dst or "") == "0.0.0.0/0") routes;
    in
    builtins.length defaults == 1
    && (builtins.head defaults).table == 1001
    && (builtins.head defaults).via == "10.1.0.23"
    && builtins.length routes == 2
'

nix_eval_true_or_fail "FS-320-HDS-010-SDS-010-SMS-030 P2 a route modelled on both sides is emitted once" \
  env REPO_ROOT="${repo_root}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --expr "${common}"'
    let
      r = { dst = "10.1.0.0/31"; via = "10.1.0.23"; table = 1001; metric = 50; };
      interfaces = {
        pdspaac = {
          renderedIfName = "pdspaac";
          routes = [ r ];
          attachTarget = { routes = [ r ]; };
        };
      };
      out = normalize.normalizedInterfacesForUnit {
        unitName = "downstream-selector"; containerName = "downstream-selector"; inherit interfaces;
      };
    in
    builtins.length out.pdspaac.routes == 1
'
