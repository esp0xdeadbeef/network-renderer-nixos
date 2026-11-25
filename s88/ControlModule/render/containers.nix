args@{
  lib,
  repoPath,
  hostPlan ? null,
  cpm ? null,
  source ? { },
  debugEnabled ? false,
  containerModelsByHost ? null,
  containerModels ? null,
  deploymentContainers ? null,
  models ? null,
  ...
}:

let

  canonicalCollections =
    if builtins.isAttrs (args.canonicalCollections or null) then args.canonicalCollections else { };

  canonicalCollection =
    name: default:
    if canonicalCollections ? ${name} && canonicalCollections.${name} != null then
      canonicalCollections.${name}
    else
      throw "FS-310-HDS-040-SDS-010-SMS-100: canonical collection '${name}' is missing from the validated bundle's canonicalCollections. This renderer cannot map it and may not reconstruct it from the plain control-plane model -- that repair is what hid the loss of published facts. Repair upstream: network-realization-schema/schema/default.nix -> bundle.canonicalCollections must list every collection the producer publishes, and network-realization-model must then project it. Do not reintroduce the fallback here.";

  requiredCollections = [
    "canonicalRoutes"
    "canonicalSites"
    "canonicalForwarding"
    "canonicalRuntimeTargets"
  ];

  _canonicalCollectionsPresent = builtins.deepSeq (map (
    name: canonicalCollection name null
  ) requiredCollections) true;

  rendered = import ./containers/default.nix (
    args
    // {

      canonicalRoutes = canonicalCollection "canonicalRoutes" [ ];
      canonicalSites = canonicalCollection "canonicalSites" { };
      canonicalForwarding = canonicalCollection "canonicalForwarding" { };

      canonicalRuntimeTargets = canonicalCollection "canonicalRuntimeTargets" { };
    }
  );
in

if builtins.isAttrs rendered && rendered == { } then
  rendered
else
  builtins.seq _canonicalCollectionsPresent rendered
