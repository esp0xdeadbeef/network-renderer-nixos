{ scope }:

let
  contract = scope.pathMtu or null;
  diagnostic = scope.pathMtuDiagnostic or null;
  hasDelegatedPrefix = builtins.isAttrs (scope.delegatedPrefix or null);

  validatedContract =
    if contract == null then
      null
    else if
      builtins.isAttrs contract
      && builtins.isInt (contract.value or null)
      && contract.value >= 1280
      && contract.value <= 65535
      && (contract.source or null) == "inventory-runtime-service"
      && (contract.sourceService or null) == "pppoe-client"
      && builtins.isString (contract.sourceTarget or null)
      && contract.sourceTarget != ""
    then
      contract
    else
      throw "FS-800-HDS-030-SDS-020-SMS-040: renderer rejected an invalid access RA path-MTU contract";

  validatedDiagnostic =
    if diagnostic == null then
      null
    else if
      builtins.isAttrs diagnostic
      && (diagnostic.traceId or null) == "FS-800-HDS-030-SDS-020-SMS-040"
      && builtins.isString (diagnostic.code or null)
      && diagnostic.code != ""
      && (diagnostic.sourceLayer or null) == "inventory"
      && builtins.isString (diagnostic.message or null)
      && diagnostic.message != ""
    then
      diagnostic
    else
      throw "FS-800-HDS-030-SDS-020-SMS-040: renderer rejected an invalid access RA path-MTU diagnostic";

  missingDiagnostic = {
    traceId = "FS-800-HDS-030-SDS-020-SMS-040";
    code = "ACCESS_RA_PATH_MTU_MISSING";
    sourceLayer = "inventory";
    message = "Runtime delegated-prefix router advertisement has no explicit uplink path-MTU contract";
  };

  effectiveDiagnostic =
    if validatedContract != null then
      null
    else if validatedDiagnostic != null then
      validatedDiagnostic
    else if hasDelegatedPrefix then
      missingDiagnostic
    else
      null;
in
{
  pathMtu = if validatedContract == null then null else validatedContract.value;
  directive =
    if validatedContract == null then "" else "AdvLinkMTU ${toString validatedContract.value};";
  warnings =
    if effectiveDiagnostic == null then
      [ ]
    else
      [ "${effectiveDiagnostic.traceId}: ${effectiveDiagnostic.code} [${effectiveDiagnostic.sourceLayer}]: ${effectiveDiagnostic.message}" ];
}
