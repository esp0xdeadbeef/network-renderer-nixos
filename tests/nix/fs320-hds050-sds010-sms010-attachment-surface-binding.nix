let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  traceId = "FS-320-HDS-050-SDS-010-SMS-010";

  surfaceModulePath = repoRoot + "/s88/Unit/physical/attachment-surface.nix";
  bindingModulePath = repoRoot + "/s88/Unit/physical/attachment-surface/binding.nix";

  surfaceModuleFile =
    if builtins.pathExists surfaceModulePath then
      surfaceModulePath
    else if builtins.pathExists bindingModulePath then
      bindingModulePath
    else
      null;

  surfaceModule =
    if surfaceModuleFile == null then null else import surfaceModuleFile { inherit lib; };

  bindingModule = if surfaceModule == null then null else surfaceModule.binding or null;

  hasBindingFunction =
    bindingModule != null && builtins.isAttrs bindingModule && bindingModule ? bindAttachmentSurface;

  bindOrNull =
    args:
    if !hasBindingFunction then
      null
    else
      let
        attempt = builtins.tryEval (bindingModule.bindAttachmentSurface args);
      in
      if attempt.success then attempt.value else null;

  surfaceClasses = [
    "physical"
    "external-bridge"
    "internal-bridge"
  ];

  attachment =
    {
      surfaceClass,
      surfaceRef,
      surfaceRefSource ? "inventory",
    }:
    {
      inherit surfaceClass surfaceRef surfaceRefSource;
      role = "access";
      direction = "ingress";
      scope = "site-access";
    };

  expressibleTarget = {
    expressibleSurfaceClasses = surfaceClasses;
    runtimeInterfaceNameRequired = false;
  };

  noBridgeTarget = {
    expressibleSurfaceClasses = [ "physical" ];
    runtimeInterfaceNameRequired = false;
  };

  noRuntimeDiscovery = noBridgeTarget // {
    runtimeDiscoveryAvailable = true;
  };

  bindPhysical =
    surfaceRef:
    bindOrNull {
      attachment = attachment {
        surfaceClass = "physical";
        inherit surfaceRef;
      };
      target = expressibleTarget;
    };

  bindExternal =
    surfaceRef:
    bindOrNull {
      attachment = attachment {
        surfaceClass = "external-bridge";
        inherit surfaceRef;
      };
      target = expressibleTarget;
    };

  bindInternal =
    surfaceRef:
    bindOrNull {
      attachment = attachment {
        surfaceClass = "internal-bridge";
        inherit surfaceRef;
      };
      target = expressibleTarget;
    };

  bindingUsesNamedSurface =
    namedSurface: binding: binding != null && (binding.surfaceRef or null) == namedSurface;

  emittedSurfaceRefs =
    bindings: lib.filter builtins.isString (map (binding: binding.surfaceRef or null) bindings);

  bindingCount = bindings: builtins.length (builtins.filter (binding: binding != null) bindings);

  physicalBinding = bindPhysical "eth-uplink";
  externalBinding = bindExternal "br-uplink";
  internalBinding = bindInternal "br-access";

  classLimitationBinding = bindOrNull {
    attachment = attachment {
      surfaceClass = "external-bridge";
      surfaceRef = "br-uplink";
    };
    target = noBridgeTarget;
  };

  discoveryBinding = bindOrNull {
    attachment = attachment {
      surfaceClass = "physical";
      surfaceRef = "eth-uplink";
    };
    target = noRuntimeDiscovery;
  };

  collapsedRecordBinding = bindOrNull {
    attachment = attachment {
      surfaceClass = "physical";
      surfaceRef = "eth99";
    };
    target = expressibleTarget;
  };

  substitutedBinding = bindOrNull {
    attachment = attachment {
      surfaceClass = "external-bridge";
      surfaceRef = "br-uplink";
    };
    target = expressibleTarget;
    candidateSurfaces = [
      "br-spare"
      "br-other"
    ];
  };

  islandSite = {
    attachments = [
      (attachment {
        surfaceClass = "external-bridge";
        surfaceRef = "br-uplink";
      })
      (attachment {
        surfaceClass = "internal-bridge";
        surfaceRef = "br-access";
      })
    ];
  };

  islandBindings = map (
    surfaceAttachment:
    bindOrNull {
      attachment = surfaceAttachment;
      target = expressibleTarget;
    }
  ) islandSite.attachments;

  islandSiteHasNoPhysicalAttachment = builtins.all (
    surfaceAttachment: surfaceAttachment.surfaceClass != "physical"
  ) islandSite.attachments;

  surfaceClassesForBindings =
    bindings:
    map (binding: binding.surfaceClass or null) (builtins.filter (binding: binding != null) bindings);

  checks = {
    surface_record_validation =
      physicalBinding != null
      && (physicalBinding.surfaceClass or null) == "physical"
      && (physicalBinding.surfaceRef or null) == "eth-uplink"
      && (physicalBinding.surfaceRefSource or null) == "inventory";

    lookup_only_binding =
      bindingUsesNamedSurface "br-uplink" externalBinding
      && bindingUsesNamedSurface "br-access" internalBinding
      && bindingUsesNamedSurface "eth-uplink" physicalBinding;

    class_limitation_reporting =
      classLimitationBinding != null
      && (classLimitationBinding.limitation or null) == "surface-class-not-expressible"
      && !(classLimitationBinding ? surfaceRef);

    substitution_rejection =
      substitutedBinding == null || (substitutedBinding.failure or null) == "substituted-surface";

    no_runtime_discovery = discoveryBinding == null;

    legal_island_acceptance =
      islandSiteHasNoPhysicalAttachment
      && bindingCount islandBindings == 2
      && builtins.all (binding: !(binding ? failure) && !(binding ? defect)) (
        builtins.filter (binding: binding != null) islandBindings
      );

    surface_class_set_is_three =
      lib.unique surfaceClasses == surfaceClasses && builtins.length surfaceClasses == 3;

    runtime_interface_name_mapping_deferred =
      !(
        internalBinding != null
        && (internalBinding ? runtimeInterfaceName)
        && (internalBinding.runtimeInterfaceName or null) != null
        && !(internalBinding ? surfaceRefAuditTarget)
      );
  };

  seededNegatives = {
    substituted_surface_rejected =
      hasBindingFunction
      && (substitutedBinding == null || (substitutedBinding.failure or null) == "substituted-surface");

    collapsed_surface_record_rejected =
      hasBindingFunction
      && (
        collapsedRecordBinding == null
        || (collapsedRecordBinding.defect or null) == "surface-record-collapsed"
        || (collapsedRecordBinding.failure or null) == "surface-record-defect"
      );
  };

  acceptance = {
    no_physical_attachment_accepted =
      islandSiteHasNoPhysicalAttachment && bindingCount islandBindings == 2;

    ungrounded_island_accepted =
      hasBindingFunction
      && bindingCount islandBindings == 2
      && builtins.all (binding: !(binding ? failure) && !(binding ? defect)) (
        builtins.filter (binding: binding != null) islandBindings
      );

    class_fallback_absent =
      hasBindingFunction && !(bindingUsesNamedSurface "br-uplink" physicalBinding);
  };

  surface_module_present = surfaceModuleFile != null;
  binding_function_present = hasBindingFunction;

  checksWithModule =
    if !hasBindingFunction then
      builtins.mapAttrs (name: _: false) checks
      // {
        surface_class_set_is_three = checks.surface_class_set_is_three;
        runtime_interface_name_mapping_deferred = false;
      }
    else
      checks;

  failed = lib.filter (name: checksWithModule.${name} != true) (builtins.attrNames checksWithModule);
in
{
  ok = failed == [ ];
  inherit failed;
  checks = checksWithModule;
  inherit seededNegatives acceptance;
  coverage = {
    inherit traceId surfaceClasses;
    surfaceModulePath = if surfaceModuleFile == null then null else toString surfaceModuleFile;
    surfaceModulePresent = surface_module_present;
    bindingFunctionPresent = binding_function_present;
    emittedSurfaceRefCount = builtins.length (emittedSurfaceRefs islandBindings);
    surfaceClassesForIslandBindings = surfaceClassesForBindings islandBindings;
  };
}
