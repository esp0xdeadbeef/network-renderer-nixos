{ lib }:

let
  asStringList =
    value:
    if value == null then
      [ ]
    else if builtins.isString value then
      [ value ]
    else if builtins.isList value then
      lib.filter builtins.isString value
    else
      [ ];

  uniqueStrings =
    values: lib.unique (lib.filter (value: builtins.isString value && value != "") values);

  bulletBlock =
    {
      title,
      values,
    }:
    let
      renderedValues = uniqueStrings values;
    in
    if renderedValues == [ ] then
      [ ]
    else
      [ "${title}:" ] ++ map (value: "  - ${value}") renderedValues;

  renderMessage =
    lines:
    builtins.concatStringsSep "\n" (lib.filter (line: builtins.isString line && line != "") lines);

  mkDesignAssumptionAlarm =
    {
      alarmId,
      summary,
      file,
      entityName ? null,
      roleName ? null,
      interfaces ? [ ],
      assumptions ? [ ],
      extraText ? [ ],
      authorityText ? null,
      source ? { },
      severity ? "warning",
    }:
    let
      message = renderMessage (
        [ "${file}: ${summary}" ]
        ++ lib.optionals (entityName != null) [ "container: ${entityName}" ]
        ++ lib.optionals (roleName != null) [ "role: ${roleName}" ]
        ++ bulletBlock {
          title = "interfaces";
          values = interfaces;
        }
        ++ bulletBlock {
          title = "renderer-only assumptions currently in use";
          values = assumptions;
        }
        ++ uniqueStrings extraText
        ++ lib.optionals (authorityText != null) [ authorityText ]
      );
    in
    {
      inherit
        alarmId
        summary
        message
        severity
        file
        assumptions
        ;
      entityName = entityName;
      roleName = roleName;
      interfaces = uniqueStrings interfaces;
      kind = "design-assumption";
      state = "active";
      source = source // {
        inherit file;
      };
      isa182 = {
        standard = "ISA-18.2";
        category = "warning";
        classification = "design-assumption";
        status = "active-unacknowledged";
        responseClass = "engineering";
      };
    };

  warningsFromAlarms = alarms: uniqueStrings (map (alarm: alarm.message or null) alarms);

  mergeModels =
    models:
    let
      alarms = lib.concatMap (
        model:
        if builtins.isAttrs model && model ? alarms && builtins.isList model.alarms then
          model.alarms
        else
          [ ]
      ) models;

      warningMessages = uniqueStrings (
        (lib.concatMap (
          model:
          if builtins.isAttrs model && model ? warningMessages && builtins.isList model.warningMessages then
            model.warningMessages
          else if builtins.isAttrs model && model ? warnings && builtins.isList model.warnings then
            model.warnings
          else
            [ ]
        ) models)
        ++ warningsFromAlarms alarms
      );
    in
    {
      inherit alarms warningMessages;
      warnings = warningMessages;
    };
in
{
  inherit
    mkDesignAssumptionAlarm
    warningsFromAlarms
    mergeModels
    ;
}
