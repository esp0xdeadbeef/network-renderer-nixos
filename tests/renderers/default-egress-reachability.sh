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
    bridgeNetdevs = bridges.netdevs or { };
    bridgeNetworks = bridges.networks or { };
    containerSet = containers.containers or { };

    access = containerSet.access-runtime or null;
    policy = containerSet.policy-runtime or null;
    upstream = containerSet.upstream-runtime or null;
    core = containerSet.core-runtime or null;

    accessVeths = if access != null && access ? extraVeths then access.extraVeths else { };
    accessArtifacts = if access != null && access ? artifactFiles then access.artifactFiles else { };
    accessFirewall =
      if builtins.hasAttr "acme/ams/hypervisor-a/containers/access-runtime/runtime-targets/access-runtime/firewall/nftables.nft" accessArtifacts then
        accessArtifacts."acme/ams/hypervisor-a/containers/access-runtime/runtime-targets/access-runtime/firewall/nftables.nft"
      else
        null;

    accessKea =
      if builtins.hasAttr "acme/ams/hypervisor-a/containers/access-runtime/services/kea/kea.json" accessArtifacts then
        accessArtifacts."acme/ams/hypervisor-a/containers/access-runtime/services/kea/kea.json"
      else
        null;

    accessRadvd =
      if builtins.hasAttr "acme/ams/hypervisor-a/containers/access-runtime/services/radvd/radvd.json" accessArtifacts then
        accessArtifacts."acme/ams/hypervisor-a/containers/access-runtime/services/radvd/radvd.json"
      else
        null;

    etcEntries =
      if artifacts ? environment && builtins.isAttrs artifacts.environment && artifacts.environment ? etc then
        artifacts.environment.etc
      else
        { };

    hasEtc = path: builtins.hasAttr path etcEntries;
  in
    builtins.isAttrs hostNetdevs
    && builtins.isAttrs hostNetworks
    && builtins.isAttrs bridgeNetdevs
    && builtins.isAttrs bridgeNetworks
    && builtins.hasAttr "br-transit" bridgeNetdevs
    && builtins.hasAttr "vlan-br-transit" bridgeNetdevs
    && builtins.hasAttr "80-br-transit" bridgeNetworks
    && builtins.hasAttr "70-vlan-br-transit" bridgeNetworks
    && access != null
    && policy != null
    && upstream != null
    && core != null
    && access.privateNetwork
    && policy.privateNetwork
    && upstream.privateNetwork
    && core.privateNetwork
    && builtins.length (builtins.attrNames accessVeths) >= 2
    && accessFirewall != null
    && accessFirewall.format == "text"
    && builtins.isString accessFirewall.value
    && accessKea != null
    && accessKea.format == "json"
    && accessRadvd != null
    && accessRadvd.format == "json"
    && hasEtc "network-artifacts/control-plane-model.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/host-data/host.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/host-data/l2/bridges.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/host-data/l2/host-adapters.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/containers/access-runtime/container.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/containers/access-runtime/runtime-targets/access-runtime/runtime-target.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/containers/access-runtime/runtime-targets/access-runtime/firewall/nftables.nft"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/containers/access-runtime/services/kea/kea.json"
    && hasEtc "network-artifacts/acme/ams/hypervisor-a/containers/access-runtime/services/radvd/radvd.json"
' >/dev/null
