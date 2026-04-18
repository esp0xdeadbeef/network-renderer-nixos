{ lib }:

let
  asList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      value
    else
      [ value ];

  flattenList =
    values:
    lib.concatMap (value: if builtins.isList value then flattenList value else [ value ]) (
      asList values
    );

  asStringList = value: lib.filter builtins.isString (flattenList value);

  uniqueStrings =
    values:
    lib.unique (lib.filter (value: builtins.isString value && value != "") (flattenList values));

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

  mkAlarm =
    {
      alarmId,
      summary,
      file,
      kind,
      classification,
      subjectLabel ? null,
      subjectValue ? null,
      roleName ? null,
      interfaces ? [ ],
      assumptions ? [ ],
      details ? [ ],
      actionItems ? [ ],
      authorityText ? null,
      source ? { },
      severity ? "warning",
    }:
    let
      message = renderMessage (
        [ "${file}: ${summary}" ]
        ++ lib.optionals (subjectLabel != null && subjectValue != null) [
          "${subjectLabel}: ${subjectValue}"
        ]
        ++ lib.optionals (roleName != null) [ "role: ${roleName}" ]
        ++ bulletBlock {
          title = "interfaces";
          values = interfaces;
        }
        ++ bulletBlock {
          title = "renderer-only assumptions currently in use";
          values = assumptions;
        }
        ++ bulletBlock {
          title = "details";
          values = details;
        }
        ++ bulletBlock {
          title = "todo";
          values = actionItems;
        }
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
        kind
        ;
      assumptions = uniqueStrings assumptions;
      roleName = roleName;
      interfaces = uniqueStrings interfaces;
      state = "active";
      source = source // {
        inherit file;
      };
      isa182 = {
        standard = "ISA-18.2";
        category = "warning";
        inherit classification;
        status = "active-unacknowledged";
        responseClass = "engineering";
      };
    };

  normalizeAlarm =
    alarm:
    if !builtins.isAttrs alarm then
      null
    else
      let
        resolvedMessage =
          if alarm ? message && builtins.isString alarm.message && alarm.message != "" then
            alarm.message
          else if alarm ? summary && builtins.isString alarm.summary && alarm.summary != "" then
            alarm.summary
          else
            null;

        resolvedInterfaces = if alarm ? interfaces then uniqueStrings alarm.interfaces else [ ];

        resolvedAssumptions = if alarm ? assumptions then uniqueStrings alarm.assumptions else [ ];

        resolvedSource = if alarm ? source && builtins.isAttrs alarm.source then alarm.source else { };

        resolvedFile =
          if alarm ? file && builtins.isString alarm.file then
            alarm.file
          else if resolvedSource ? file && builtins.isString resolvedSource.file then
            resolvedSource.file
          else
            null;
      in
      if resolvedMessage == null then
        null
      else
        alarm
        // {
          message = resolvedMessage;
          interfaces = resolvedInterfaces;
          assumptions = resolvedAssumptions;
          source =
            resolvedSource
            // lib.optionalAttrs (resolvedFile != null) {
              file = resolvedFile;
            };
        }
        // lib.optionalAttrs (resolvedFile != null) {
          file = resolvedFile;
        };

  alarmsFromValue =
    value:
    lib.filter (alarm: alarm != null) (
      map normalizeAlarm (
        if builtins.isAttrs value && value ? alarms then
          flattenList value.alarms
        else if builtins.isList value then
          flattenList value
        else if builtins.isAttrs value then
          [ value ]
        else
          [ ]
      )
    );

  warningsFromAlarms =
    alarms: uniqueStrings (map (alarm: alarm.message or null) (alarmsFromValue alarms));

  warningMessagesFromValue =
    value:
    let
      directWarnings =
        if builtins.isAttrs value then
          uniqueStrings (
            (if value ? warningMessages then value.warningMessages else [ ])
            ++ (if value ? warnings then value.warnings else [ ])
          )
        else if builtins.isString value then
          [ value ]
        else if builtins.isList value then
          uniqueStrings value
        else
          [ ];

      alarmWarnings = warningsFromAlarms (alarmsFromValue value);
    in
    uniqueStrings (directWarnings ++ alarmWarnings);

  normalizeModel =
    model:
    let
      alarms = alarmsFromValue model;
      warningMessages = warningMessagesFromValue model;
    in
    {
      inherit alarms warningMessages;
      warnings = warningMessages;
    };

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
    mkAlarm {
      inherit
        alarmId
        summary
        file
        roleName
        interfaces
        assumptions
        source
        severity
        authorityText
        ;
      kind = "design-assumption";
      classification = "design-assumption";
      subjectLabel = "container";
      subjectValue = entityName;
      details = extraText;
      actionItems = [ ];
    };

  mkImplementationWarningAlarm =
    {
      alarmId,
      summary,
      file,
      component ? null,
      roleName ? null,
      interfaces ? [ ],
      details ? [ ],
      todo ? [ ],
      authorityText ? null,
      source ? { },
      severity ? "warning",
    }:
    mkAlarm {
      inherit
        alarmId
        summary
        file
        roleName
        interfaces
        source
        severity
        authorityText
        ;
      kind = "implementation-warning";
      classification = "implementation-gap";
      subjectLabel = "component";
      subjectValue = component;
      assumptions = [ ];
      inherit details;
      actionItems = todo;
    };

  mergeModels =
    models:
    let
      normalizedModels = map normalizeModel (flattenList models);

      alarms = lib.concatMap (model: model.alarms) normalizedModels;

      warningMessages = uniqueStrings (
        (lib.concatMap (model: model.warningMessages) normalizedModels) ++ warningsFromAlarms alarms
      );
    in
    {
      inherit alarms warningMessages;
      warnings = warningMessages;
    };
in
{
  inherit
    asStringList
    mkDesignAssumptionAlarm
    mkImplementationWarningAlarm
    warningsFromAlarms
    normalizeModel
    mergeModels
    ;
}
