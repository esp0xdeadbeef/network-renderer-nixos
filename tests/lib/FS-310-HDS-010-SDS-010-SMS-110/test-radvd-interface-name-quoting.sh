#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-module-test
#
# The RA file radvd is given must be a file radvd accepts.
#
# radvd's grammar has no dedicated token for an interface name: it reuses the
# generic STRING rule, which prefers the keyword table. An interface whose name
# is one of radvd's own keywords is therefore a syntax error on the FIRST line
# of the generated file, and radvd exits before advertising anything:
#
#     interface clients { ... };   ->  radvd-clients.conf:1 error: syntax error
#
# Measured against radvd 2.21, bare vs quoted:
#
#     clients  prefix  route  dnssl  abro  interface   bare: syntax error
#     clients  prefix  route  dnssl  abro  interface  quoted: syntax ok
#
# This is not a hypothetical name. The site model names the tenant-facing access
# interface `clients` (and `iot`, `dmz`, `mgmt`, `svc`, `unlock`), so every
# tenant link whose name collides with a radvd keyword silently got no router
# advertisements. Measured on the cobalt HAT guest before the fix:
# `radvd-clients.service` restart-looped 1792 times, the tenant had a
# link-local address only, `ip -6 route show default` was empty and `ping -6`
# returned "Network is unreachable" -- while IPv4 on the same link worked. No
# layer above the renderer reported an error.
#
# `lib.escapeShellArg` is NOT the fix: it is a no-op for a plain name such as
# `clients`, which is precisely how the defect survived the first attempt. The
# assertion is therefore on radvd's own grammar (the real binary, check mode),
# not on a list of keywords someone guessed.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

case_dir="$(mktemp -d)"
trap 'rm -rf "${case_dir}"' EXIT

# The radvd keywords that a site model could plausibly use as a tenant interface
# name. `clients` is the one that actually broke cobalt.
keywords=(clients prefix route dnssl abro interface)

# 1. Render the generator for each keyword-named interface.
REPO_ROOT="${repo_root}" KEYWORDS="${keywords[*]}" nix eval --impure --json --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    flake = builtins.getFlake ("path:" + repoRoot);
    lib = flake.inputs.nixpkgs.lib;
    keywords = lib.splitString " " (builtins.getEnv "KEYWORDS");
    baseScope = {
      fileStem = "test";
      delegatedPrefix = null;
      prefixes = [ "fd42:1::/64" ];
      rdnss = [ "fd42:1::1" ];
      domain = "lan.";
      managed = false;
      otherConfig = false;
      onLink = true;
      autonomous = true;
      defaultRoute = true;
    };
    mockPkgs = {
      writeShellScript = _name: text: text;
      iproute2 = "/nix/store/mock-iproute2";
      gnugrep = "/nix/store/mock-gnugrep";
      python3 = "/nix/store/mock-python3";
      radvd = "/nix/store/mock-radvd";
      coreutils = "/nix/store/mock-coreutils";
      gnused = "/nix/store/mock-gnused";
      systemd = "/nix/store/mock-systemd";
    };
    render =
      interfaceName:
      (import (repoRoot + "/s88/ControlModule/access/render/radvd.nix") {
        inherit lib;
        pkgs = mockPkgs;
        scope = baseScope // { inherit interfaceName; };
      }).systemd.services."radvd-generate-test".serviceConfig.ExecStart;
  in
  builtins.listToAttrs (map (name: { inherit name; value = render name; }) keywords)
' > "${case_dir}/scripts.json"

# 2. The real radvd binary: the assertion is its grammar, not our keyword list.
radvd_bin="$(nix build --no-link --print-out-paths --impure --expr '
  (builtins.getFlake "path:'"${repo_root}"'").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.radvd
' | tail -1)/bin/radvd"

# 3. Extract each config from its generator script. Done in Python because the
# script spans many lines and emits more than one heredoc.
python3 - "${case_dir}" <<'PY'
import json, os, re, sys

case_dir = sys.argv[1]
scripts = json.load(open(os.path.join(case_dir, "scripts.json")))
for name, script in sorted(scripts.items()):
    match = re.search(r"cat > /run/radvd-[^ ]*\.conf <<.EOF.\n(.*?)\nEOF", script, re.S)
    body = match.group(1) if match else ""
    with open(os.path.join(case_dir, "radvd-" + name + ".conf"), "w") as handle:
        handle.write(body + "\n" if body else "")
PY

failures=()
failed=0
for name in "${keywords[@]}"; do
  cfg="${case_dir}/radvd-${name}.conf"
  if [[ ! -s "${cfg}" ]]; then
    failures+=("${name}: generator wrote no radvd config")
    failed=1
    continue
  fi
  if ! grep -qF "interface \"${name}\" {" "${cfg}"; then
    failures+=("${name}: generator did not quote the interface name")
    failed=1
    continue
  fi
  if ! "${radvd_bin}" -C "${cfg}" -c > "${case_dir}/out" 2>&1 || grep -q "syntax error" "${case_dir}/out"; then
    failures+=("${name}: radvd rejected the generated config: $(tr '\n' ' ' < "${case_dir}/out")")
    failed=1
  fi
done

if (( failed )); then
  printf 'FAIL radvd-interface-name-quoting:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
  exit 1
fi

pass "radvd-interface-name-quoting (${keywords[*]})"
