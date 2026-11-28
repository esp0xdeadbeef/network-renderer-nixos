{ lib }:

{
  runtimeTarget,
  unitName ? "<unknown>",
}:
let
  fact =
    if
      builtins.isAttrs runtimeTarget && builtins.isAttrs (runtimeTarget.policyRoutingSources or null)
    then
      runtimeTarget.policyRoutingSources
    else
      null;
in
if fact != null then
  fact
else
  throw "FS-310-HDS-020-SDS-010-SMS-060: the model supplies no 'policyRoutingSources' for runtime target '${unitName}'. A renderer may not decide which interfaces feed a policy table: the answer decides where the table's rules apply, and a renderer-chosen answer is indistinguishable from a modelled one in the output. The control-plane model publishes this record on every runtime target (policy-routing-facts.nix); the bundle must carry it through."
