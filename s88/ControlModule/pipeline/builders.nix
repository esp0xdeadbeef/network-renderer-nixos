{
  lib,
  flakeInputs,
  currentSystem ? builtins.currentSystem,
}:

let
  selectors = import ../lookup/host-query.nix { inherit lib; };
  isa = import ../alarm/isa18.nix { inherit lib; };

  isControlPlaneLike =
    value:
    builtins.isAttrs value
    && (
      (
        value ? control_plane_model
        && builtins.isAttrs value.control_plane_model
        && value.control_plane_model ? data
        && builtins.isAttrs value.control_plane_model.data
      )
      || (value ? data && builtins.isAttrs value.data)
    );

  withForwardingModel =
    forwardingOut: result:
    if builtins.isAttrs result then result // { forwardingModel = forwardingOut; } else result;

  appendAlarmModel =
    value: alarmModel:
    let
      normalized = isa.normalizeModel alarmModel;
    in
    if !builtins.isAttrs value || (normalized.alarms == [ ] && normalized.warningMessages == [ ]) then
      value
    else
      let
        merged = isa.mergeModels [
          value
          normalized
        ];
      in
      value
      // {
        alarms = merged.alarms;
        warningMessages = merged.warningMessages;
        warnings = merged.warnings;
      };

  propagateAlarmModel = upstream: downstream: appendAlarmModel downstream upstream;

  forwardingSubstitutionWarningModel =
    {
      system,
      substituteSource,
      substituteInputSource,
    }:
    isa.normalizeModel [
      (isa.mkImplementationWarningAlarm {
        alarmId = "pipeline-forwarding-substitution";
        summary = "forwarding output was produced by a substitute pipeline stage";
        file = "s88/CM/network/pipeline/builders.nix";
        component = "buildForwarding";
        details = [
          "flake input 'network-forwarding-model' was not used for system '${system}'"
          "substitute forwarding source: ${substituteSource}"
          "substitute input source: ${substituteInputSource}"
          "renderer is currently accepting substitute forwarding-shaped output so downstream evaluation can continue"
        ];
        todo = [
          "replace this substitution path with authoritative 'network-forwarding-model' output"
        ];
        authorityText = "Network forwarding model should provide the authoritative forwarding output consumed by the renderer.";
        source = {
          stage = "buildForwarding";
          inherit
            system
            substituteSource
            substituteInputSource
            ;
        };
      })
    ];

  buildCompiler =
    {
      intent,
      system ? currentSystem,
    }:
    if
      flakeInputs ? nixos-network-compiler
      && flakeInputs.nixos-network-compiler ? lib
      && flakeInputs.nixos-network-compiler.lib ? compile
    then
      (flakeInputs.nixos-network-compiler.lib.compile system) intent
    else
      throw "s88/CM/network/pipeline/builders.nix: flake input 'nixos-network-compiler' with lib.compile is required";

  buildForwarding =
    {
      compilerOut,
      system ? currentSystem,
    }:
    if
      flakeInputs ? network-forwarding-model
      && flakeInputs.network-forwarding-model ? lib
      && builtins.hasAttr system flakeInputs.network-forwarding-model.lib
    then
      let
        impl = flakeInputs.network-forwarding-model.lib.${system};
      in
      if builtins.isFunction impl then
        impl { input = compilerOut; }
      else if builtins.isAttrs impl && impl ? build then
        impl.build { input = compilerOut; }
      else
        throw "s88/CM/network/pipeline/builders.nix: flake input 'network-forwarding-model' has unsupported API shape"
    else if
      flakeInputs ? network-control-plane-model
      && flakeInputs.network-control-plane-model ? lib
      && builtins.hasAttr system flakeInputs.network-control-plane-model.lib
    then
      let
        impl = flakeInputs.network-control-plane-model.lib.${system};

        fallbackResult =
          if builtins.isFunction impl then
            impl { input = compilerOut; }
          else
            throw "s88/CM/network/pipeline/builders.nix: flake input 'network-control-plane-model' cannot build forwarding output from compiler output";

        warningModel = forwardingSubstitutionWarningModel {
          inherit system;
          substituteSource = "network-control-plane-model";
          substituteInputSource = "nixos-network-compiler";
        };
      in
      appendAlarmModel fallbackResult warningModel
    else
      throw "s88/CM/network/pipeline/builders.nix: flake input 'network-forwarding-model' or function-shaped 'network-control-plane-model' is required";

  buildControlPlane =
    {
      forwardingOut,
      inventory,
      system ? currentSystem,
    }:
    if
      flakeInputs ? network-control-plane-model
      && flakeInputs.network-control-plane-model ? lib
      && builtins.hasAttr system flakeInputs.network-control-plane-model.lib
    then
      let
        impl = flakeInputs.network-control-plane-model.lib.${system};
      in
      if builtins.isAttrs impl && impl ? build then
        propagateAlarmModel forwardingOut (
          withForwardingModel forwardingOut (
            impl.build {
              input = forwardingOut;
              inherit inventory;
            }
          )
        )
      else if builtins.isFunction impl then
        let
          result = impl { input = forwardingOut; };

          realized = if builtins.isFunction result then result { inherit inventory; } else result;
        in
        propagateAlarmModel forwardingOut (withForwardingModel forwardingOut realized)
      else if isControlPlaneLike forwardingOut then
        propagateAlarmModel forwardingOut (withForwardingModel forwardingOut forwardingOut)
      else
        throw "s88/CM/network/pipeline/builders.nix: flake input 'network-control-plane-model' has unsupported API shape"
    else if isControlPlaneLike forwardingOut then
      propagateAlarmModel forwardingOut (withForwardingModel forwardingOut forwardingOut)
    else
      throw "s88/CM/network/pipeline/builders.nix: flake input 'network-control-plane-model' is required";

  buildCompilerFromPaths =
    {
      intentPath,
      system ? currentSystem,
    }:
    buildCompiler {
      intent = selectors.importMaybeFunction (builtins.toPath intentPath);
      inherit system;
    };

  buildForwardingFromPaths =
    {
      intentPath,
      system ? currentSystem,
    }:
    buildForwarding {
      compilerOut = buildCompilerFromPaths {
        inherit intentPath system;
      };
      inherit system;
    };

  buildControlPlaneFromPaths =
    {
      intentPath,
      inventoryPath,
      system ? currentSystem,
    }:
    buildControlPlane {
      forwardingOut = buildForwardingFromPaths {
        inherit intentPath system;
      };
      inventory = selectors.importMaybeFunction (builtins.toPath inventoryPath);
      inherit system;
    };
in
{
  inherit
    buildCompiler
    buildForwarding
    buildControlPlane
    buildCompilerFromPaths
    buildForwardingFromPaths
    buildControlPlaneFromPaths
    ;
}
