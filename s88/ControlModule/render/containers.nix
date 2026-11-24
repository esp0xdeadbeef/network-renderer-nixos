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
  # FS-310-HDS-040-SDS-010-SMS-100 (canonical-only consumption, no raw CPM).
  #
  # This helper used to REPAIR a missing canonical collection: when the bundle
  # did not carry `name` it reached into `args.cpm` -- the plain control-plane
  # model, under `model` or under its own name -- and returned the producer's
  # field instead. That is not a fallback, it is the renderer undoing a loss it
  # is not allowed to see: the bundle projection in network-realization-model
  # drops a collection the schema does not list (see `canonicalFor` there), and
  # this read put the dropped collection back, so the bundle's completeness was
  # never observable and no renderer ever failed for the reason the model lost
  # the fact.
  #
  # The fallback is gone. A renderer maps `canonicalCollections`; if the bundle
  # does not carry a collection this renderer needs, the render fails here and
  # names the collection. The repair belongs upstream -- schema, then producer,
  # then the renderer's derivation -- and doing it here makes it invisible.
  #
  # The `default` parameter stays because the call sites below pass one and they
  # are not part of this change: it is no longer reachable. A silent default is
  # the defect this throw replaces.
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

  # Forced, not lazy. `canonicalRoutes` and friends are attributes of a lazy
  # attrset, so the helper above would only throw for a model that happened to
  # force the collection it is missing -- and the interesting case (a render that
  # silently produces nothing) never forces it. Rendering a host whose bundle
  # carries no canonical content must fail, so the check runs at evaluation.
  _canonicalCollectionsPresent = builtins.deepSeq (
    map (name: canonicalCollection name null) requiredCollections
  ) true;

in
builtins.seq _canonicalCollectionsPresent (
  import ./containers/default.nix (
    args
    // {

      canonicalRoutes = canonicalCollection "canonicalRoutes" [ ];
      canonicalSites = canonicalCollection "canonicalSites" { };
      canonicalForwarding = canonicalCollection "canonicalForwarding" { };

      canonicalRuntimeTargets = canonicalCollection "canonicalRuntimeTargets" { };
    }
  )
)
