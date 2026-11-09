#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-035
# GAMP-SCOPE: software-module-test
#
# A registered DNS upstream set is runtime material: encrypted at rest, delivered
# as a secret reference, decrypted inside the consuming resolver, and only then
# materialized into the forward zone. These cases assert the decryption contract
# with keys generated for this run, so no operator key and no committed secret is
# involved.
#
# The predicate under test is not "sops runs". It is: the ciphertext is bound to
# exactly the recipients the target holds, the plaintext never appears outside
# the runtime material, and the delivered set is non-empty and usable before the
# resolver consumes it. Each negative case is seeded (the violation is
# constructed), asserts the specific failure, and then asserts that correcting
# that violation restores acceptance.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

fail() {
  echo "FAIL FS-540-HDS-010-SDS-010-SMS-035: $*" >&2
  exit 1
}

pass() {
  echo "PASS FS-540-HDS-010-SDS-010-SMS-035: $*"
}

for cmd in age-keygen sops nix python3; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing required command: ${cmd}"
done

# This test must not consume any operator identity or the repository's SOPS
# creation rules: every identity below is generated in this run. Clear the
# ambient variables so a runner that happens to export one cannot make the
# assertions pass for the wrong reason, and run from a scratch directory so no
# .sops.yaml creation rule is discovered.
unset SOPS_AGE_KEY SOPS_AGE_KEY_FILE SOPS_AGE_KEY_CMD SOPS_AGE_RECIPIENTS
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

decrypt_failure="Failed to get the data key required to decrypt the SOPS file"

# ── fixture: one age identity for the target, one that is not the target ──────
age-keygen -o "${tmp}/target.key" 2>"${tmp}/target.pub"
age-keygen -o "${tmp}/other.key" 2>"${tmp}/other.pub"
target_pub="$(sed -n 's/^Public key: //p' "${tmp}/target.pub")"
other_pub="$(sed -n 's/^Public key: //p' "${tmp}/other.pub")"
[ -n "$target_pub" ] || fail "could not read the generated age public key"
[ -n "$other_pub" ] || fail "could not read the second generated age public key"
[ "$target_pub" != "$other_pub" ] || fail "generated identities are not distinct"

printf '1.1.1.1\n1.0.0.1\n' >"${tmp}/dnsNth"

encrypt_to() {
  local pub=$1 out=$2
  SOPS_AGE_KEY_FILE="${tmp}/target.key" sops \
    --encrypt --age "$pub" --input-type binary --output-type binary \
    "${tmp}/dnsNth" >"$out"
}

decrypt_with() {
  local key=$1 src=$2 out=$3
  SOPS_AGE_KEY_FILE="$key" sops \
    --decrypt --input-type binary --output-type binary "$src" >"$out" 2>"${out}.err"
}

# ── 1. round-trip: the target identity recovers the exact delivered bytes ────
encrypt_to "$target_pub" "${tmp}/dnsNth.enc"
decrypt_with "${tmp}/target.key" "${tmp}/dnsNth.enc" "${tmp}/plain"
cmp -s "${tmp}/dnsNth" "${tmp}/plain" \
  || fail "decrypted material does not match the delivered bytes"
pass "target identity decrypts the delivered set byte-for-byte"

# ── 2. redaction: the encrypted reference carries no plaintext address ───────
if grep -qE '1\.1\.1\.1|1\.0\.0\.1' "${tmp}/dnsNth.enc"; then
  fail "the delivered reference carries a plaintext upstream address"
fi
pass "delivered reference carries no plaintext upstream address"

# ── 3. seeded negative: an identity that is not the target cannot decrypt ────
set +e
decrypt_with "${tmp}/other.key" "${tmp}/dnsNth.enc" "${tmp}/wrong"
wrong_rc=$?
set -e
[ "$wrong_rc" -ne 0 ] \
  || fail "an identity outside the recipient set decrypted the material"
grep -qF "$decrypt_failure" "${tmp}/wrong.err" \
  || fail "non-recipient decryption failed without the expected diagnostic:
$(cat "${tmp}/wrong.err")"
if [ -s "${tmp}/wrong" ]; then
  fail "non-recipient decryption still wrote plaintext"
fi
decrypt_with "${tmp}/target.key" "${tmp}/dnsNth.enc" "${tmp}/plain.ok"
cmp -s "${tmp}/dnsNth" "${tmp}/plain.ok" \
  || fail "restoring the target identity did not restore acceptance"
pass "non-recipient identity rejected, target identity restores acceptance"

# ── 4. seeded negative: tampered ciphertext is rejected ─────────────────────
python3 - "${tmp}/dnsNth.enc" "${tmp}/dnsNth.tampered" <<'PY'
import sys
source, target = sys.argv[1], sys.argv[2]
data = bytearray(open(source, "rb").read())
if not data:
    raise SystemExit("empty ciphertext fixture")
data[len(data) // 2] ^= 0xFF
open(target, "wb").write(data)
PY
set +e
decrypt_with "${tmp}/target.key" "${tmp}/dnsNth.tampered" "${tmp}/tampered"
tampered_rc=$?
set -e
[ "$tampered_rc" -ne 0 ] || fail "a tampered ciphertext decrypted successfully"
cp "${tmp}/dnsNth.enc" "${tmp}/dnsNth.restored"
decrypt_with "${tmp}/target.key" "${tmp}/dnsNth.restored" "${tmp}/plain.restored"
cmp -s "${tmp}/dnsNth" "${tmp}/plain.restored" \
  || fail "restoring the untampered ciphertext did not restore acceptance"
pass "tampered ciphertext rejected, untampered ciphertext restores acceptance"

# ── 5. recipient rotation: both old and new identity decrypt the same bytes ──
SOPS_AGE_KEY_FILE="${tmp}/target.key" sops \
  --encrypt --age "$target_pub,$other_pub" --input-type binary --output-type binary \
  "${tmp}/dnsNth" >"${tmp}/rotated.enc"
decrypt_with "${tmp}/target.key" "${tmp}/rotated.enc" "${tmp}/rot.target"
decrypt_with "${tmp}/other.key" "${tmp}/rotated.enc" "${tmp}/rot.other"
cmp -s "${tmp}/dnsNth" "${tmp}/rot.target" \
  || fail "rotation removed the existing identity's access"
cmp -s "${tmp}/dnsNth" "${tmp}/rot.other" \
  || fail "rotation did not grant the added identity access"
pass "multi-recipient rotation keeps both identities able to decrypt"

# ── 6. the delivered shape is exactly the address set ──────────────────────
{
  printf '# primary\n'
  printf '  1.1.1.1  \n'
  printf '\n'
  printf '1.0.0.1\t# failover\n'
} >"${tmp}/dnsNth.commented"
SOPS_AGE_KEY_FILE="${tmp}/target.key" sops \
  --encrypt --age "$target_pub" --input-type binary --output-type binary \
  "${tmp}/dnsNth.commented" >"${tmp}/commented.enc"
decrypt_with "${tmp}/target.key" "${tmp}/commented.enc" "${tmp}/commented.plain"

# Mirror the renderer's registered-upstream reader exactly: it reads one address
# per LINE, strips an inline '#' comment, strips whitespace within the line, and
# skips empty lines (s88/ControlModule/render/containers/dns-services.nix,
# registeredUpstreamMaterializer). Joining lines would merge the last octet of
# one address with the first of the next, so the parse stays line-oriented.
awk '{
  sub(/#.*/, "");
  gsub(/[[:space:]]/, "");
  if ($0 == "") next;
  print
}' "${tmp}/commented.plain" | sort >"${tmp}/parsed.actual"
printf '1.0.0.1\n1.1.1.1\n' >"${tmp}/parsed.expected"
cmp -s "${tmp}/parsed.expected" "${tmp}/parsed.actual" \
  || fail "address parsing produced '$(paste -sd, "${tmp}/parsed.actual")' instead of the declared set"
pass "comments and whitespace reduce to exactly the declared address set"

# ── 7. seeded negative: an empty set is unusable, a populated one is usable ─
: >"${tmp}/dnsNth.empty"
SOPS_AGE_KEY_FILE="${tmp}/target.key" sops \
  --encrypt --age "$target_pub" --input-type binary --output-type binary \
  "${tmp}/dnsNth.empty" >"${tmp}/empty.enc"
decrypt_with "${tmp}/target.key" "${tmp}/empty.enc" "${tmp}/empty.plain"
empty_count="$(awk '/([0-9]{1,3}\.){3}[0-9]{1,3}/ { n++ } END { print n + 0 }' "${tmp}/empty.plain")"
[ "$empty_count" -eq 0 ] \
  || fail "the empty fixture unexpectedly carried ${empty_count} address(es)"
decrypt_with "${tmp}/target.key" "${tmp}/dnsNth.enc" "${tmp}/usable.plain"
usable_count="$(awk '/([0-9]{1,3}\.){3}[0-9]{1,3}/ { n++ } END { print n + 0 }' "${tmp}/usable.plain")"
[ "$usable_count" -eq 2 ] \
  || fail "the populated fixture carried ${usable_count} address(es), expected 2"
pass "empty material is distinguishable from a populated set (0 vs 2 addresses)"

# ── 8. the renderer consumes the reference, not the plaintext ──────────────
wiring="$(
  REPO_ROOT="$repo_root" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        system = builtins.currentSystem;
        pkgs = import flake.inputs.nixpkgs { inherit system; };
        lib = flake.inputs.nixpkgs.lib;
        module = import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
          inherit lib pkgs;
          renderedModel = {
            runtimeTarget.services.dns = {
              recursionMode = "forwarding";
              listen = [ "192.0.2.53" ];
              allowFrom = [ "192.0.2.0/24" ];
              registeredUpstreams = [
                {
                  sourceFile = "/run/secrets/cobalt-dns-upstreams";
                  family = "ipv4";
                }
              ];
            };
          };
          forwardingIntent = { };
        };
        unit = module.systemd.services.dns-registered-upstream or null;
      in
        {
          rendered = unit != null;
          exec = if unit == null then "" else unit.serviceConfig.ExecStart or "";
          before = if unit == null then [ ] else unit.before or [ ];
          unboundInclude = module.services.unbound.settings.include or [ ];
        }
    ' 2>"${tmp}/wiring.err"
)"

python3 - "$wiring" <<'PY' || { cat "${tmp}/wiring.err" >&2; fail "renderer wiring assertions failed"; }
import json, sys
data = json.loads(sys.argv[1])
problems = []
if not data["rendered"]:
    problems.append("dns-registered-upstream unit was not rendered")
if "dns-registered-upstream-materializer" not in data["exec"]:
    problems.append(f"ExecStart does not run the materializer: {data['exec']!r}")
if "/run/secrets/cobalt-dns-upstreams" not in data["exec"]:
    problems.append(f"ExecStart does not read the secret reference: {data['exec']!r}")
if "unbound.service" not in data["before"]:
    problems.append(f"unit does not run before unbound.service: {data['before']!r}")
if "/run/unbound/registered-upstream.conf" not in data["unboundInclude"]:
    problems.append(
        f"unbound does not include the materialized file: {data['unboundInclude']!r}"
    )
if problems:
    print("\n".join(problems), file=sys.stderr)
    raise SystemExit(1)
PY
pass "renderer reads the secret reference, materializes before unbound, and includes the result"

echo ""
echo "──────────────────────────────────────────"
echo "PASS FS-540-HDS-010-SDS-010-SMS-035 registered upstream decryption (8 cases)"
