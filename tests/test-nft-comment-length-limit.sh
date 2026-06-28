#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL nft-comment-length-limit: $*" >&2
  exit 1
}

long_comment='core-transit-mesh--link::esp0xdeadbeef.site-a::p2p-nixos-core-testnet-routed-isp-nixos-upstream-selector--pppoe-session::esp0xdeadbeef-site-a-nixos-core-testnet-routed-isp::ppp1'
(( ${#long_comment} > 128 )) || fail "fixture comment is not longer than nft limit"

rules="$(
  REPO_ROOT="${repo_root}" LONG_COMMENT="${long_comment}" nix eval --impure --raw --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      longComment = builtins.getEnv "LONG_COMMENT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      escapeComment = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;
      renderRuleset = import (repoRoot + "/s88/ControlModule/firewall/emission/render-ruleset.nix") { inherit lib; };
      renderExplicit = import (repoRoot + "/s88/ControlModule/firewall/policy/explicit-forwarding.nix") {
        inherit lib escapeComment;
        forwardingIntent.normalizedExplicitForwardPairs = [
          {
            "in" = [ "ens21" ];
            "out" = [ "ppp1" ];
            action = "accept";
            comment = longComment;
          }
        ];
      };
    in
      (renderRuleset {
        forwardPairs = [
          {
            "in" = [ "ens21" ];
            "out" = [ "ppp1" ];
            action = "accept";
            comment = longComment;
          }
        ];
      })
      + "\n"
      + builtins.concatStringsSep "\n" renderExplicit
  '
)"

if grep -F -- "${long_comment}" <<<"${rules}" >/dev/null; then
  fail "rendered nft rules still contain the overlong source comment"
fi

comment_count=0
while IFS= read -r token; do
  value="${token#comment \"}"
  value="${value%\"}"
  comment_count=$((comment_count + 1))
  if (( ${#value} > 128 )); then
    fail "rendered nft comment exceeds 128 chars (${#value}): ${value}"
  fi
done < <(grep -o 'comment "[^"]*"' <<<"${rules}")

(( comment_count >= 2 )) || fail "expected comments from both nft emitters"

echo "PASS nft-comment-length-limit"
