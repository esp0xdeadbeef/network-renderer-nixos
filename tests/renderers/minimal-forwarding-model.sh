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

    hostNetdevs = host.netdevs or { };
    hostNetworks = host.networks or { };
    hostUplink = hostNetdevs.br-runtime-a or null;
    hostUplinkNetwork = hostNetworks."20-br-runtime-a" or null;

    bridgeNetdevs = bridges.netdevs or { };
    bridgeNetworks = bridges.networks or { };

    containerSet = containers.containers or { };

    etcEntries =
      if artifacts ? environment && builtins.isAttrs artifacts.environment && artifacts.environment ? etc then
        artifacts.environment.etc
      else
        { };
  in
    host.hostName == "hypervisor-a"
    && builtins.isAttrs hostNetdevs
    && builtins.isAttrs hostNetworks
    && hostUplink != null
    && hostUplink.netdevConfig.Kind == "bridge"
    && hostUplink.netdevConfig.Name == "br-runtime-a"
    && hostUplinkNetwork != null
    && hostUplinkNetwork.matchConfig.Name == "br-runtime-a"
    && hostUplinkNetwork.networkConfig.ConfigureWithoutCarrier
    && builtins.isAttrs bridgeNetdevs
    && builtins.isAttrs bridgeNetworks
    && containerSet == { }
    && builtins.hasAttr "network-artifacts/control-plane-model.json" etcEntries
' >/dev/null
