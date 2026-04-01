#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: ./test-split-box-render.sh <intent.nix> <inventory.nix> [render.json]" >&2
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$script_dir"

intent_path="$(realpath "$1")"
inventory_path="$(realpath "$2")"
render_json_input="${3:-./90-render.json}"
render_json="$(realpath "$render_json_input")"

if [ ! -f "$intent_path" ]; then
  echo "[!] Missing intent path: $intent_path" >&2
  exit 1
fi

if [ ! -f "$inventory_path" ]; then
  echo "[!] Missing inventory path: $inventory_path" >&2
  exit 1
fi

if [ ! -f "$render_json" ]; then
  echo "[!] Missing render JSON: $render_json" >&2
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

nix_quote() {
  printf '%s' "$1" | jq -Rsa .
}

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mapfile -t boxes < <(jq -r '.hosts | keys[]' "$render_json")

if [ "${#boxes[@]}" -eq 0 ]; then
  echo "[!] No hosts found in render JSON: $render_json" >&2
  exit 1
fi

for box in "${boxes[@]}"; do
  echo "[*] Validating split box renderer for ${box}"

  identities_json_path="$tmpdir/${box}.identities.json"
  expected_json="$tmpdir/${box}.expected.json"
  actual_json="$tmpdir/${box}.actual.json"

  jq -cer --arg box "$box" '
    [
      .nodes
      | to_entries[]
      | select(.value.deploymentHostName == $box)
      | {
          enterpriseName: (.value.logicalNode.enterprise // null),
          siteName: (.value.logicalNode.site // null)
        }
      | select(.enterpriseName != null and .siteName != null)
    ]
    | unique
    | if length > 0 then
        .
      else
        error("could not infer enterprise/site identities for box " + $box)
      end
  ' "$render_json" >"$identities_json_path"

  jq -c --arg box "$box" '
    {
      netdevs: (.hosts[$box].network.netdevs // {}),
      networks: (.hosts[$box].network.networks // {}),
      containers: (.containers[$box] // {})
    }
  ' "$render_json" >"$expected_json"

  repo_root_nix="$(nix_quote "$repo_root")"
  intent_path_nix="$(nix_quote "$intent_path")"
  inventory_path_nix="$(nix_quote "$inventory_path")"
  identities_path_nix="$(nix_quote "$identities_json_path")"
  box_name_nix="$(nix_quote "$box")"

  expr="$(cat <<EOF
let
  flake = builtins.getFlake (toString (builtins.toPath ${repo_root_nix}));
  nixpkgsLib = flake.lib.flakeInputs.nixpkgs.lib;
  api = flake.lib;

  identities = builtins.fromJSON (builtins.readFile (builtins.toPath ${identities_path_nix}));
  boxName = ${box_name_nix};

  sortedAttrNames = attrs: nixpkgsLib.sort builtins.lessThan (builtins.attrNames attrs);

  mergeAttrs = values: builtins.foldl' (acc: value: acc // value) { } values;

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
    in
    {
      autoStart = container.autoStart or false;
      privateNetwork = container.privateNetwork or false;
      extraVeths = container.extraVeths or { };
      bindMounts = container.bindMounts or { };
      allowedDevices = container.allowedDevices or [ ];
      additionalCapabilities = container.additionalCapabilities or [ ];
      inherit firewall;
      specialArgs = {
        unitName = if specialArgs ? unitName then specialArgs.unitName else containerName;
        deploymentHostName =
          if specialArgs ? deploymentHostName then specialArgs.deploymentHostName else null;
        s88RoleName = if specialArgs ? s88RoleName then specialArgs.s88RoleName else null;
      };
    };

  sanitizeContainers =
    containers:
    builtins.listToAttrs (
      map
        (containerName: {
          name = containerName;
          value = sanitizeContainer containerName containers.\${containerName};
        })
        (sortedAttrNames containers)
    );

  tryRenderSlice =
    identity:
    let
      attempt = builtins.tryEval (
        let
          host = api.host.build {
            lib = nixpkgsLib;
            enterpriseName = identity.enterpriseName;
            siteName = identity.siteName;
            boxName = boxName;
            intentPath = ${intent_path_nix};
            inventoryPath = ${inventory_path_nix};
          };

          bridges = api.bridges.build {
            lib = nixpkgsLib;
            enterpriseName = identity.enterpriseName;
            siteName = identity.siteName;
            boxName = boxName;
            intentPath = ${intent_path_nix};
            inventoryPath = ${inventory_path_nix};
          };

          containers = api.containers.buildForBox {
            lib = nixpkgsLib;
            enterpriseName = identity.enterpriseName;
            siteName = identity.siteName;
            boxName = boxName;
            intentPath = ${intent_path_nix};
            inventoryPath = ${inventory_path_nix};
            defaults = { };
            disabled = { };
          };

          rendered = {
            netdevs = (host.netdevs or { }) // (bridges.netdevs or { });
            networks = (host.networks or { }) // (bridges.networks or { });
            containers = sanitizeContainers containers;
          };
        in
        builtins.deepSeq rendered rendered
      );
    in
    if attempt.success then attempt.value else null;

  renderedSlices = nixpkgsLib.filter (slice: slice != null) (map tryRenderSlice identities);
in
if renderedSlices == [ ] then
  throw "test-split-box-render: no split slices rendered successfully for \${boxName}"
else
  {
    netdevs = mergeAttrs (map (slice: slice.netdevs) renderedSlices);
    networks = mergeAttrs (map (slice: slice.networks) renderedSlices);
    containers = mergeAttrs (map (slice: slice.containers) renderedSlices);
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
done

echo "[*] Split box renderer validation passed"
