{
  lib,
  lookupSiteServiceInputs,
  mapFirewallForwardingRuntimeTargetModel,
  mapFirewallPolicyRuntimeTargetModel,
}:
{
  normalizedModel,
  artifactContext,
}:
let
  ensureAttrs =
    name: value:
    if builtins.isAttrs value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be an attribute set";

  ensureString =
    name: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a non-empty string";

  ensureBool =
    name: value:
    if builtins.isBool value then
      value
    else
      throw "network-renderer-nixos: expected ${name} to be a boolean";

  context = ensureAttrs "artifactContext" artifactContext;

  runtimeTarget =
    if context ? runtimeTarget then
      ensureAttrs "artifactContext.runtimeTarget" context.runtimeTarget
    else
      throw "network-renderer-nixos: artifactContext is missing runtimeTarget";

  role =
    if runtimeTarget ? role then
      ensureString "artifactContext.runtimeTarget.role" runtimeTarget.role
    else
      null;

  forwardingResponsibility =
    if runtimeTarget ? forwardingResponsibility then
      ensureAttrs "artifactContext.runtimeTarget.forwardingResponsibility" runtimeTarget.forwardingResponsibility
    else
      { };

  enforcesPolicy =
    if forwardingResponsibility ? enforcesPolicy then
      ensureBool "artifactContext.runtimeTarget.forwardingResponsibility.enforcesPolicy" forwardingResponsibility.enforcesPolicy
    else
      false;

  _policyContextValid =
    if !(enforcesPolicy || role == "policy") then
      true
    else if
      !(context ? enterpriseName)
      || !(builtins.isString context.enterpriseName)
      || context.enterpriseName == ""
    then
      throw "network-renderer-nixos: policy firewall selection requires artifactContext.enterpriseName"
    else if
      !(context ? siteName) || !(builtins.isString context.siteName) || context.siteName == ""
    then
      throw "network-renderer-nixos: policy firewall selection requires artifactContext.siteName"
    else
      true;

  _validateSiteInputs =
    if !(enforcesPolicy || role == "policy") then
      true
    else
      let
        _siteInputs = lookupSiteServiceInputs {
          inherit normalizedModel;
          enterpriseName = context.enterpriseName;
          siteName = context.siteName;
        };
      in
      builtins.seq _siteInputs true;
in
builtins.seq _policyContextValid (
  builtins.seq _validateSiteInputs (
    if enforcesPolicy || role == "policy" then
      mapFirewallPolicyRuntimeTargetModel {
        inherit
          normalizedModel
          artifactContext
          ;
      }
    else
      mapFirewallForwardingRuntimeTargetModel artifactContext
  )
)
