{
  lib,
  selectFirewallRuntimeTargetModel,
  renderNftablesRuntimeTarget,
  selectContainerRuntimeTargetServiceModels,
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

  context = ensureAttrs "artifactContext" artifactContext;

  enterpriseName = context.enterpriseName;
  siteName = context.siteName;
  hostName = context.hostName;
  containerName = context.containerName;
  runtimeTargetName = context.runtimeTargetName;
  runtimeTarget = ensureAttrs "artifactContext.runtimeTarget" context.runtimeTarget;

  firewallArtifact =
    if runtimeTarget ? forwardingIntent && builtins.isAttrs runtimeTarget.forwardingIntent then
      {
        format = "text";
        value = renderNftablesRuntimeTarget (selectFirewallRuntimeTargetModel {
          inherit normalizedModel;
          artifactContext = context;
        });
      }
    else
      null;

  selectedServices = selectContainerRuntimeTargetServiceModels { artifactContext = context; };

  serviceEntries = lib.filter (entry: entry != null) [
    (
      if selectedServices.kea == null then
        null
      else
        {
          name = "${context.servicesRoot}/kea/kea.json";
          value = {
            format = "json";
            value = selectedServices.kea;
          };
        }
    )
    (
      if selectedServices.radvd == null then
        null
      else
        {
          name = "${context.servicesRoot}/radvd/radvd.json";
          value = {
            format = "json";
            value = selectedServices.radvd;
          };
        }
    )
  ];

  serviceNames = map (entry: builtins.elemAt (lib.splitString "/" entry.name) 4) serviceEntries;

  files = {
    "${context.containerArtifactPath}" = {
      format = "json";
      value = {
        enterprise = enterpriseName;
        site = siteName;
        host = hostName;
        container = containerName;
        artifactPath = context.containerArtifactPath;
        runtimeTargetNames = [ runtimeTargetName ];
        runtimeTargetArtifactPaths = [ context.runtimeTargetArtifactPath ];
        serviceNames = serviceNames;
      };
    };

    "${context.runtimeTargetArtifactPath}" = {
      format = "json";
      value = runtimeTarget;
    };
  }
  // lib.optionalAttrs (serviceEntries != [ ]) {
    "${context.servicesRoot}/index.json" = {
      format = "json";
      value = {
        enterprise = enterpriseName;
        site = siteName;
        host = hostName;
        container = containerName;
        artifactPath = "${context.servicesRoot}/index.json";
        serviceNames = serviceNames;
        runtimeTargetNames = [ runtimeTargetName ];
        runtimeTargetArtifactPaths = [ context.runtimeTargetArtifactPath ];
      };
    };
  }
  // builtins.listToAttrs serviceEntries
  // lib.optionalAttrs (firewallArtifact != null) {
    "${context.firewallArtifactPath}" = firewallArtifact;
  };
in
{
  inherit files;
  nftablesArtifactPath = if firewallArtifact == null then null else context.firewallArtifactPath;
}
