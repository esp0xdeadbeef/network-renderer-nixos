{ mkAlarm }:

{
  mkDesignAssumptionAlarm =
    { alarmId
    , summary
    , file
    , entityName ? null
    , roleName ? null
    , interfaces ? [ ]
    , assumptions ? [ ]
    , extraText ? [ ]
    , authorityText ? null
    , source ? { }
    , severity ? "warning"
    ,
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
    { alarmId
    , summary
    , file
    , component ? null
    , roleName ? null
    , interfaces ? [ ]
    , details ? [ ]
    , todo ? [ ]
    , authorityText ? null
    , source ? { }
    , severity ? "warning"
    ,
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
}
