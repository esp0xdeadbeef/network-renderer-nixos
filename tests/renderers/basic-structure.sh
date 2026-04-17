#!/usr/bin/env bash

set -euo pipefail

host_json="$1"
bridges_json="$2"
containers_json="$3"
artifacts_json="$4"

HOST_JSON="${host_json}" \
BRIDGES_JSON="${bridges_json}" \
CONTAINERS_JSON="${containers_json}" \
ARTIFACTS_JSON="${artifacts_json}" \
nix eval --impure --expr '
  let
    host = builtins.fromJSON (builtins.readFile (builtins.getEnv "HOST_JSON"));
    bridges = builtins.fromJSON (builtins.readFile (builtins.getEnv "BRIDGES_JSON"));
    containers = builtins.fromJSON (builtins.readFile (builtins.getEnv "CONTAINERS_JSON"));
    artifacts = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARTIFACTS_JSON"));

    hostOk = builtins.isAttrs host && host ? netdevs && host ? networks;
    bridgesOk = builtins.isAttrs bridges && bridges ? netdevs && bridges ? networks;
    containersOk = builtins.isAttrs containers && containers ? containers && builtins.isAttrs containers.containers;
    artifactsOk =
      builtins.isAttrs artifacts
      && artifacts ? environment
      && builtins.isAttrs artifacts.environment
      && artifacts.environment ? etc
      && builtins.isAttrs artifacts.environment.etc;
  in
    hostOk && bridgesOk && containersOk && artifactsOk
' >/dev/null
