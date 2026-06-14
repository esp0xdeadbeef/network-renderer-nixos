#!/usr/bin/env bash

example_scan_root() {
  local labs_root
  labs_root="$(flake_input_path network-labs)"
  printf '%s\n' "${NETWORK_RENDERER_NIXOS_EXAMPLE_ROOT:-${labs_root}/examples}"
}

example_dirs() {
  local root="$1"

  if [[ -f "${root}/intent.nix" ]]; then
    printf '%s\n' "${root}"
  else
    find "${root}" -mindepth 2 -maxdepth 2 -type f -name intent.nix -printf '%h\n' | sort
  fi
}

render_example_dry_json() {
  local example_dir="$1"
  local tmp_dir="$2"
  local output_json="$3"

  local intent_path="${example_dir}/intent.nix"
  local inventory_path="${example_dir}/inventory-nixos.nix"

  if [[ -f "${example_dir}/getResolvedInventory.nix" ]]; then
    inventory_path="${tmp_dir}/inventory-nixos-resolved.nix"
    cat >"${inventory_path}" <<EOF
import ${example_dir}/getResolvedInventory.nix { renderer = "nixos"; }
EOF
  fi

  (
    cd "${tmp_dir}"
    build_cpm_json "${intent_path}" "${inventory_path}" "${tmp_dir}/cpm.json"

    REPO_ROOT="${repo_root}" \
    CPM_PATH="${tmp_dir}/cpm.json" \
    INVENTORY_PATH="${inventory_path}" \
      nix eval \
        --extra-experimental-features 'nix-command flakes' \
        --impure --json \
        --expr '
          let
            flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          in
          flake.lib.renderer.renderDryConfig {
            cpmPath = builtins.getEnv "CPM_PATH";
            exampleDir = builtins.dirOf (builtins.getEnv "CPM_PATH");
            debug = true;
          }
        ' >"${output_json}"
  )
}

run_example_render_scan() {
  local check_name="$1"
  local callback="$2"
  local root
  root="$(example_scan_root)"

  [[ -d "${root}" ]] || fail "!!!! ${check_name}: missing network-labs examples root: ${root}"

  local ran=0
  local skipped=0
  local failed=0
  local violations
  violations="$(mktemp)"

  while IFS= read -r example_dir; do
    [[ -n "${example_dir}" ]] || continue
    if [[ ! -f "${example_dir}/inventory-nixos.nix" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    ran=$((ran + 1))
    local tmp_dir
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-renderer-nixos-${check_name}.XXXXXX")"

    if render_example_dry_json "${example_dir}" "${tmp_dir}" "${tmp_dir}/dry.json"; then
      "${callback}" "${example_dir}" "${tmp_dir}/dry.json" >>"${violations}"
    else
      echo "!!!! ${check_name}: render crashed for ${example_dir}" >>"${violations}"
      failed=1
    fi

    rm -rf "${tmp_dir}"
  done < <(example_dirs "${root}")

  if (( ran == 0 )); then
    rm -f "${violations}"
    fail "!!!! ${check_name}: no runnable network-labs/examples fixtures under ${root}"
  fi

  if [[ -s "${violations}" ]]; then
    cat "${violations}" >&2
    rm -f "${violations}"
    fail "!!!! ${check_name}: PROD-UNSAFE selector/firewall contract violation; scanned=${ran} skipped=${skipped}"
  fi

  rm -f "${violations}"
  if (( failed != 0 )); then
    fail "!!!! ${check_name}: render failure while scanning examples"
  fi

  pass "${check_name} scanned=${ran} skipped=${skipped}"
}
