{ renderedInterfaceNames
, policyRoutingSources ? { }
,
}:

{
  mayProject =
    targetName: sourceIfName:
    let
      sourceName = renderedInterfaceNames.${sourceIfName};
      sources = policyRoutingSources.${targetName} or [ ];
    in
    builtins.elem sourceIfName sources || builtins.elem sourceName sources;
}
