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

  forwardingIntent =
    if runtimeTarget ? forwardingIntent then
      ensureAttrs "artifactContext.runtimeTarget.forwardingIntent" runtimeTarget.forwardingIntent
    else
      { };

  forwardingMode =
    if forwardingIntent ? mode then
      ensureString "artifactContext.runtimeTarget.forwardingIntent.mode" forwardingIntent.mode
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

  useExplicitForwardingModel = forwardingMode == "explicit-transit-mesh-forwarding";
in
if useExplicitForwardingModel then
  mapFirewallForwardingRuntimeTargetModel context
else if enforcesPolicy || role == "policy" then
  mapFirewallPolicyRuntimeTargetModel {
    inherit
      normalizedModel
      artifactContext
      ;
  }
else
  mapFirewallForwardingRuntimeTargetModel context
