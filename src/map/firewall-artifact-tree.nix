{
  lib,
  mapRuntimeTargetArtifactContexts,
  selectFirewallRuntimeTargetModel,
  renderNftablesRuntimeTarget,
}:
{ normalizedModel }:
let
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

  runtimeTargetHasRenderableForwardingRules =
    runtimeTarget:
    runtimeTarget ? forwardingIntent
    && builtins.isAttrs runtimeTarget.forwardingIntent
    && runtimeTarget.forwardingIntent ? rules
    && builtins.isList runtimeTarget.forwardingIntent.rules
    && runtimeTarget.forwardingIntent.rules != [ ];

  runtimeTargetContexts = mapRuntimeTargetArtifactContexts {
    inherit normalizedModel;
  };

  firewallContextNames = lib.filter (
    contextName:
    let
      context = runtimeTargetContexts.${contextName};
      runtimeTarget =
        if context ? runtimeTarget && builtins.isAttrs context.runtimeTarget then
          context.runtimeTarget
        else
          null;
    in
    runtimeTarget != null && runtimeTargetHasRenderableForwardingRules runtimeTarget
  ) (sortedAttrNames runtimeTargetContexts);

  fileEntries = lib.concatMap (
    contextName:
    let
      context = runtimeTargetContexts.${contextName};
      firewallModel = selectFirewallRuntimeTargetModel {
        inherit normalizedModel;
        artifactContext = context;
      };
      renderedRules = renderNftablesRuntimeTarget firewallModel;
    in
    [
      {
        name = "${context.artifactPathPrefix}/firewall/nftables.nft";
        value = {
          format = "text";
          value = renderedRules;
        };
      }
    ]
  ) firewallContextNames;

  filePaths = map (entry: entry.name) fileEntries;

  _uniquePaths =
    if builtins.length filePaths == builtins.length (lib.unique filePaths) then
      true
    else
      throw "network-renderer-nixos: firewall artifact rendering produced duplicate paths";
in
builtins.seq _uniquePaths (builtins.listToAttrs fileEntries)
