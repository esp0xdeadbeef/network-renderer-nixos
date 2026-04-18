#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: ./test-split-box-render.sh <control-plane.(nix|json)> [render.json]" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$script_dir"

cpm_path="$(realpath "$1")"
render_json_input="${2:-./90-render.json}"
render_json="$(realpath "$render_json_input")"

if [ ! -f "$cpm_path" ]; then
  echo "[!] Missing CPM path: $cpm_path" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[!] Required command not found: $1" >&2
    exit 1
  }
}

require_cmd jq
require_cmd nix
require_cmd diff
require_cmd cp

nix_quote() {
  printf '%s' "$1" | jq -Rsa .
}

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

render_json_snapshot="$tmpdir/render.json"

if [ -f "$render_json" ]; then
  cp "$render_json" "$render_json_snapshot"
else
  # Generate render.json from CPM using the s88 app.
  (
    cd "$tmpdir"
    nix run \
      --no-write-lock-file \
      --extra-experimental-features 'nix-command flakes' \
      "$repo_root"#render-dry-config \
      -- \
      --debug \
      "$cpm_path" \
      >/dev/null
    cp ./90-render.json "$render_json_snapshot"
  )
fi

mapfile -t boxes < <(jq -r '.hosts | keys[]' "$render_json_snapshot")

if [ "${#boxes[@]}" -eq 0 ]; then
  echo "[!] No hosts found in render JSON: $render_json_snapshot" >&2
  exit 1
fi

for box in "${boxes[@]}"; do
  echo "[*] Validating split box renderer for ${box}"

  expected_json="$tmpdir/${box}.expected.json"
  actual_json="$tmpdir/${box}.actual.json"
  expected_container_names_json="$tmpdir/${box}.expected-container-names.json"
  actual_container_names_json="$tmpdir/${box}.actual-container-names.json"

  jq -c --arg box "$box" '
    {
      netdevs: (.hosts[$box].network.netdevs // {}),
      networks: (.hosts[$box].network.networks // {}),
      containers: (.containers[$box] // {})
    }
  ' "$render_json_snapshot" >"$expected_json"

  repo_root_nix="$(nix_quote "$repo_root")"
  cpm_path_nix="$(nix_quote "$cpm_path")"
  box_name_nix="$(nix_quote "$box")"

  expr="$(cat <<EOF
let
  flake = builtins.getFlake (toString (builtins.toPath ${repo_root_nix}));
  nixpkgsLib = flake.lib.flakeInputs.nixpkgs.lib;
  api = flake.lib.renderer;
  cpm = api.loadControlPlane (builtins.toPath ${cpm_path_nix});
  inventory =
    if builtins.isAttrs cpm && cpm ? globalInventory && builtins.isAttrs cpm.globalInventory then
      cpm.globalInventory
    else if builtins.isAttrs cpm && cpm ? inventory && builtins.isAttrs cpm.inventory then
      cpm.inventory
    else
      { };
  boxName = ${box_name_nix};

  sortedAttrNames = attrs: nixpkgsLib.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeDebug =
    raw:
    if !builtins.isAttrs raw then
      { }
    else
      builtins.removeAttrs raw [ "profilePath" ];

  sanitizeFirewall =
    rawFirewall:
    if builtins.isAttrs rawFirewall then
      {
        enable = rawFirewall.enable or false;
        ruleset = if rawFirewall ? ruleset then rawFirewall.ruleset else null;
      }
    else if builtins.isString rawFirewall then
      {
        enable = rawFirewall != "";
        ruleset = rawFirewall;
      }
    else
      {
        enable = false;
        ruleset = null;
      };

  sanitizeContainer =
    containerName: container:
    let
      specialArgs =
        if container ? specialArgs && builtins.isAttrs container.specialArgs then
          container.specialArgs
        else
          { };

      firewall =
        if specialArgs ? s88Firewall then
          sanitizeFirewall specialArgs.s88Firewall
        else
          {
            enable = false;
            ruleset = null;
          };

      s88Debug =
        if specialArgs ? s88Debug && builtins.isAttrs specialArgs.s88Debug then
          sanitizeDebug specialArgs.s88Debug
        else
          { };

      s88Warnings =
        if specialArgs ? s88Warnings && builtins.isList specialArgs.s88Warnings then
          nixpkgsLib.filter builtins.isString specialArgs.s88Warnings
        else
          [ ];

      s88Alarms =
        if specialArgs ? s88Alarms && builtins.isList specialArgs.s88Alarms then
          specialArgs.s88Alarms
        else
          [ ];
    in
    {
      autoStart = container.autoStart or false;
      privateNetwork = container.privateNetwork or false;
      extraVeths = container.extraVeths or { };
      bindMounts = container.bindMounts or { };
      allowedDevices = container.allowedDevices or [ ];
      additionalCapabilities = container.additionalCapabilities or [ ];
      inherit firewall;
      warnings = s88Warnings;
      alarms = s88Alarms;
      specialArgs = {
        unitName = if specialArgs ? unitName then specialArgs.unitName else containerName;
        deploymentHostName =
          if specialArgs ? deploymentHostName then specialArgs.deploymentHostName else null;
        s88RoleName = if specialArgs ? s88RoleName then specialArgs.s88RoleName else null;
        s88Debug = s88Debug;
      };
    };

  sanitizeContainers =
    containers:
    builtins.listToAttrs (
      map (containerName: {
        name = containerName;
        value = sanitizeContainer containerName containers.\${containerName};
      }) (sortedAttrNames containers)
    );

  hostRendering = api.renderHostNetwork {
    hostName = boxName;
    cpm = cpm;
    inventory = inventory;
  };
in
{
  netdevs = hostRendering.netdevs or { };
  networks = hostRendering.networks or { };
  containers = sanitizeContainers (hostRendering.containers or { });
}
EOF
)"

  nix eval \
    --impure \
    --json \
    --extra-experimental-features 'nix-command flakes' \
    --expr "$expr" \
    >"$actual_json"

  if ! diff -u <(jq -S . "$expected_json") <(jq -S . "$actual_json"); then
    echo "[!] Split box renderer mismatch for ${box}" >&2
    echo "[!] Expected: ${expected_json}" >&2
    echo "[!] Actual:   ${actual_json}" >&2
    exit 1
  fi

  jq -c '(.containers // {}) | keys' "$expected_json" >"$expected_container_names_json"
  jq -c '(.containers // {}) | keys' "$actual_json" >"$actual_container_names_json"

  if ! diff -u <(jq -S . "$expected_container_names_json") <(jq -S . "$actual_container_names_json"); then
    echo "[!] Split box container set mismatch for ${box}" >&2
    echo "[!] Expected: ${expected_container_names_json}" >&2
    echo "[!] Actual:   ${actual_container_names_json}" >&2
    exit 1
  fi

  mapfile -t containers < <(jq -r '.[]' "$expected_container_names_json")

  for container in "${containers[@]}"; do
    echo "[*] Validating split container renderer for ${container}"

    expected_container_json="$tmpdir/${box}.${container}.expected-container.json"
    actual_container_json="$tmpdir/${box}.${container}.actual-container.json"

    jq -c --arg container "$container" '.containers[$container]' "$expected_json" >"$expected_container_json"
    jq -c --arg container "$container" '.containers[$container]' "$actual_json" >"$actual_container_json"

    if ! diff -u <(jq -S . "$expected_container_json") <(jq -S . "$actual_container_json"); then
      echo "[!] Split container renderer mismatch for ${container} on ${box}" >&2
      echo "[!] Expected: ${expected_container_json}" >&2
      echo "[!] Actual:   ${actual_container_json}" >&2
      exit 1
    fi
  done
done

echo "[*] Split box renderer validation passed"
