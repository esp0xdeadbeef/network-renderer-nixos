{ lib }:

{
  runtimeTarget,
  unitName ? "<unknown>",
}:
let
  fact =
    if builtins.isAttrs runtimeTarget && builtins.isAttrs (runtimeTarget.networkBehavior or null) then
      runtimeTarget.networkBehavior
    else
      null;
in
if fact != null then
  fact
else
  throw "FS-310-HDS-020-SDS-010-SMS-060: the model supplies no 'networkBehavior' for runtime target '${unitName}'. This renderer will not decide a target's role from interface topology, and it will not default the role: a wrong role puts interface routes in the main table or keeps them out of it, and either answer changes which table a packet uses. The control-plane model publishes this record on every runtime target (policy-routing-facts.nix); the bundle must carry it through."
