{
outPath,
lib,
config,
hostContext ? { },
globalInventory ? { },
...
}:

let
runtimeContext = import ./runtime-context.nix { inherit lib; };

sortedAttrNames = attrs:
lib.sort builtins.lessThan (builtins.attrNames attrs);

queried = (import ./host-query.nix { inherit lib; }).queryFromOutPath {
inherit outPath;
hostname = config.networking.hostName;
file = "lib/s88-unit.nix";
};

resolvedHostContext =
if hostContext != { } then hostContext else queried.hostContext;

resolvedInventory =
if globalInventory != { } then globalInventory else queried.globalInventory;

deploymentHostName =
if resolvedHostContext ? deploymentHostName
&& builtins.isString resolvedHostContext.deploymentHostName
then
resolvedHostContext.deploymentHostName
else
config.networking.hostName;

controlPlaneOut =
if resolvedHostContext ? controlPlaneOut then
resolvedHostContext.controlPlaneOut
else
null;

roles = import ./s88-role-registry.nix { inherit lib; };

deploymentHostUnitNames =
if controlPlaneOut != null then
runtimeContext.unitNamesForDeploymentHost {
cpm = controlPlaneOut;
inventory = resolvedInventory;
inherit deploymentHostName;
file = "lib/s88-unit.nix";
}
else
[ ];

activeRoleNames =
if controlPlaneOut != null then
lib.filter
(roleName: builtins.hasAttr roleName roles)
(
lib.unique (
map
(unitName:
runtimeContext.roleForUnit {
cpm = controlPlaneOut;
inventory = resolvedInventory;
inherit unitName;
file = "lib/s88-unit.nix";
})
deploymentHostUnitNames
)
)
else
[ ];

activeRoles =
builtins.listToAttrs (
map
(roleName: {
name = roleName;
value = roles.${roleName};
})
activeRoleNames
);

s88RoleName =
if builtins.length activeRoleNames == 1 then
builtins.head activeRoleNames
else
null;

s88Role =
if s88RoleName != null then
roles.${s88RoleName}
else
null;

_validatedRoles =
if controlPlaneOut == null || activeRoleNames != [ ] then
true
else
throw "lib/s88-unit.nix: could not resolve any router roles for deployment host '${deploymentHostName}'";
in
{
imports = [
"${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
../s88/CM/network/default.nix
];

_module.args = {
inherit (queried) fabricInputs;
inherit resolvedHostContext activeRoleNames activeRoles s88Role s88RoleName;
globalInventory = resolvedInventory;
hostContext = resolvedHostContext;
};
}
