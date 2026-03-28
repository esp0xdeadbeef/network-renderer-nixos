{ lib }:

let
sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);

controlPlaneData = cpm:
if cpm ? control_plane_model
&& builtins.isAttrs cpm.control_plane_model
&& cpm.control_plane_model ? data
&& builtins.isAttrs cpm.control_plane_model.data
then
cpm.control_plane_model.data
else if cpm ? data && builtins.isAttrs cpm.data then
cpm.data
else
{ };

siteTreeForEnterprise = enterprise:
if enterprise ? site && builtins.isAttrs enterprise.site then
enterprise.site
else if builtins.isAttrs enterprise then
enterprise
else
{ };

siteEntries = cpm:
let
cpmData = controlPlaneData cpm;
in
lib.concatMap
(enterpriseName:
let
siteTree = siteTreeForEnterprise cpmData.${enterpriseName};
in
map
(siteName: {
inherit enterpriseName siteName;
site = siteTree.${siteName};
})
(sortedAttrNames siteTree))
(sortedAttrNames cpmData);

runtimeTargets = cpm:
lib.foldl'
(acc: entry:
acc
// (
if entry.site ? runtimeTargets && builtins.isAttrs entry.site.runtimeTargets then
entry.site.runtimeTargets
else
{ }
))
{ }
(siteEntries cpm);

siteEntryForUnit =
{
cpm,
unitName,
file ? "lib/runtime-context.nix",
}:
let
matches =
lib.filter
(entry:
entry.site ? runtimeTargets
&& builtins.isAttrs entry.site.runtimeTargets
&& builtins.hasAttr unitName entry.site.runtimeTargets)
(siteEntries cpm);
in
if builtins.length matches == 1 then
builtins.head matches
else if matches == [ ] then
throw ''
${file}: no site entry matched unit '${unitName}'
''
else
throw ''
${file}: multiple site entries matched unit '${unitName}'
'';

runtimeTargetForUnit =
{
cpm,
unitName,
file ? "lib/runtime-context.nix",
}:
let
targets = runtimeTargets cpm;
in
if builtins.hasAttr unitName targets && builtins.isAttrs targets.${unitName} then
targets.${unitName}
else
throw ''
${file}: missing runtime target for unit '${unitName}'

known runtime targets:
${builtins.concatStringsSep "\n  - " ([ "" ] ++ sortedAttrNames targets)}
'';

logicalNodeForUnit =
{
cpm,
inventory,
unitName,
file ? "lib/runtime-context.nix",
}:
let
target = runtimeTargetForUnit {
inherit cpm unitName file;
};

realizationNode =
if inventory ? realization
&& builtins.isAttrs inventory.realization
&& inventory.realization ? nodes
&& builtins.isAttrs inventory.realization.nodes
&& builtins.hasAttr unitName inventory.realization.nodes
then
inventory.realization.nodes.${unitName}
else
null;
in
if target ? logicalNode && builtins.isAttrs target.logicalNode then
target.logicalNode
else if realizationNode != null
&& realizationNode ? logicalNode
&& builtins.isAttrs realizationNode.logicalNode
then
realizationNode.logicalNode
else
{ };

roleForUnit =
{
cpm,
inventory,
unitName,
file ? "lib/runtime-context.nix",
}:
let
target = runtimeTargetForUnit {
inherit cpm unitName file;
};

logicalNode = logicalNodeForUnit {
inherit cpm inventory unitName file;
};
in
if target ? role && builtins.isString target.role then
target.role
else
logicalNode.role or null;

deploymentHostForUnit =
{
cpm,
inventory,
unitName,
file ? "lib/runtime-context.nix",
}:
let
target = runtimeTargetForUnit {
inherit cpm unitName file;
};

realizationNode =
if inventory ? realization
&& builtins.isAttrs inventory.realization
&& inventory.realization ? nodes
&& builtins.isAttrs inventory.realization.nodes
&& builtins.hasAttr unitName inventory.realization.nodes
then
inventory.realization.nodes.${unitName}
else
null;

targetPlacementHost =
if target ? placement then
if builtins.isAttrs target.placement then
if target.placement ? host then
if builtins.isString target.placement.host then
target.placement.host
else
throw ''
${file}: runtime target for unit '${unitName}' has non-string placement.host

runtime target:
${builtins.toJSON target}
''
else
null
else
throw ''
${file}: runtime target for unit '${unitName}' has non-attr placement

runtime target:
${builtins.toJSON target}
''
else
null;

realizationHost =
if realizationNode != null && realizationNode ? host then
if builtins.isString realizationNode.host then
realizationNode.host
else
throw ''
${file}: realization node for unit '${unitName}' has non-string host

realization node:
${builtins.toJSON realizationNode}
''
else
null;
in
if targetPlacementHost != null && realizationHost != null then
if targetPlacementHost == realizationHost then
targetPlacementHost
else
throw ''
${file}: conflicting deployment hosts for unit '${unitName}'

runtime target placement.host: ${targetPlacementHost}
realization node host: ${realizationHost}

runtime target:
${builtins.toJSON target}

realization node:
${builtins.toJSON realizationNode}
''
else if targetPlacementHost != null then
targetPlacementHost
else if realizationHost != null then
realizationHost
else
throw ''
${file}: missing deployment host for unit '${unitName}'

runtime target:
${builtins.toJSON target}

realization node:
${builtins.toJSON realizationNode}
'';

connectivityKindNames = [
"bridge"
"direct"
"tenant"
"wan"
"fabric"
"loopback"
"provider"
"service"
];

connectivityKindsForInterface = iface:
lib.filter
(kindName:
builtins.hasAttr kindName iface
&& (
builtins.isAttrs iface.${kindName}
|| builtins.isString iface.${kindName}
|| builtins.isBool iface.${kindName}
))
connectivityKindNames;

validateStringField =
{
value,
fieldName,
unitName,
ifName ? null,
file ? "lib/runtime-context.nix",
context ? { },
}:
if builtins.isString value then
true
else
throw ''
${file}: expected string field '${fieldName}'${
if ifName != null then " on interface '${ifName}'" else ""
} for unit '${unitName}'

context:
${builtins.toJSON context}
'';

validateListField =
{
value,
fieldName,
unitName,
ifName ? null,
file ? "lib/runtime-context.nix",
context ? { },
}:
if builtins.isList value then
true
else
throw ''
${file}: expected list field '${fieldName}'${
if ifName != null then " on interface '${ifName}'" else ""
} for unit '${unitName}'

context:
${builtins.toJSON context}
'';

validateInterfaceForUnit =
{
unitName,
ifName,
iface,
file ? "lib/runtime-context.nix",
}:
let
_connectivityKinds = connectivityKindsForInterface iface;
_hasCanonicalConnectivityField =
iface ? connectivity && (
builtins.isAttrs iface.connectivity
|| builtins.isString iface.connectivity
);
in
assert validateStringField {
value = iface.renderedIfName or null;
fieldName = "renderedIfName";
inherit unitName ifName file;
context = iface;
};
assert validateStringField {
value = iface.hostBridge or null;
fieldName = "hostBridge";
inherit unitName ifName file;
context = iface;
};
assert validateListField {
value = iface.addresses or [ ];
fieldName = "addresses";
inherit unitName ifName file;
context = iface;
};
assert validateListField {
value = iface.routes or [ ];
fieldName = "routes";
inherit unitName ifName file;
context = iface;
};
if _hasCanonicalConnectivityField then
true
else if builtins.length _connectivityKinds == 1 then
true
else if builtins.length _connectivityKinds == 0 then
throw ''
${file}: interface '${ifName}' for unit '${unitName}' is missing connectivity data

interface:
${builtins.toJSON iface}
''
else
throw ''
${file}: interface '${ifName}' for unit '${unitName}' exposes multiple connectivity types

connectivity kinds:
${builtins.toJSON _connectivityKinds}

interface:
${builtins.toJSON iface}
'';

validateRuntimeTargetForUnit =
{
cpm,
inventory,
unitName,
file ? "lib/runtime-context.nix",
}:
let
target = runtimeTargetForUnit {
inherit cpm unitName file;
};

_interfaces =
if target ? interfaces && builtins.isAttrs target.interfaces then
target.interfaces
else
throw ''
${file}: missing canonical runtime interfaces for unit '${unitName}'

runtime target:
${builtins.toJSON target}
'';

_validateDeploymentHost = deploymentHostForUnit {
inherit cpm inventory unitName file;
};

_validateInterfaces =
map
(ifName:
validateInterfaceForUnit {
inherit unitName ifName file;
iface = _interfaces.${ifName};
})
(sortedAttrNames _interfaces);
in
true;

validateAllRuntimeTargets =
{
cpm,
inventory,
file ? "lib/runtime-context.nix",
}:
let
targets = runtimeTargets cpm;
_validations =
map
(unitName:
validateRuntimeTargetForUnit {
inherit cpm inventory unitName file;
})
(sortedAttrNames targets);
in
true;

unitNamesForDeploymentHost =
{
cpm,
inventory,
deploymentHostName,
file ? "lib/runtime-context.nix",
}:
let
targets = runtimeTargets cpm;
in
lib.filter
(unitName:
deploymentHostForUnit {
inherit cpm inventory unitName file;
} == deploymentHostName)
(sortedAttrNames targets);

unitNamesForRoleOnDeploymentHost =
{
cpm,
inventory,
deploymentHostName,
role,
file ? "lib/runtime-context.nix",
}:
let
targets = runtimeTargets cpm;
in
lib.filter
(unitName:
roleForUnit {
inherit cpm inventory unitName file;
} == role
&& deploymentHostForUnit {
inherit cpm inventory unitName file;
} == deploymentHostName)
(sortedAttrNames targets);

enterpriseNamesForUnit =
{
cpm,
unitName,
file ? "lib/runtime-context.nix",
}:
let
entry = siteEntryForUnit {
inherit cpm unitName file;
};
in
[ entry.enterpriseName ];

siteNamesForUnit =
{
cpm,
unitName,
file ? "lib/runtime-context.nix",
}:
let
entry = siteEntryForUnit {
inherit cpm unitName file;
};
in
[ entry.siteName ];

in
{
inherit
siteEntries
runtimeTargets
siteEntryForUnit
runtimeTargetForUnit
logicalNodeForUnit
roleForUnit
deploymentHostForUnit
validateInterfaceForUnit
validateRuntimeTargetForUnit
validateAllRuntimeTargets
unitNamesForDeploymentHost
unitNamesForRoleOnDeploymentHost
enterpriseNamesForUnit
siteNamesForUnit
;
}
