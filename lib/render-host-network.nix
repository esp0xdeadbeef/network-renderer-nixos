{ lib, inventory, hostName, cpm ? null }:

let
realizationPorts = import ./realization-ports.nix { inherit lib; };
tenantBridgeRenderer = import ./tenant-bridge-renderer.nix { inherit lib; };

maxLen = 15;

hash = name:
builtins.substring 0 6 (builtins.hashString "sha256" name);

shorten = name:
if builtins.stringLength name <= maxLen then
name
else
let
prefixLen = maxLen - 7;
prefix = builtins.substring 0 prefixLen name;
in
"${prefix}-${hash name}";

ensureUnique =
names:
let
shortened =
map
(n: {
original = n;
rendered = shorten n;
})
names;

grouped =
builtins.foldl'
(acc: entry:
let key = entry.rendered;
in acc // {
${key} = (acc.${key} or [ ]) ++ [ entry.original ];
})
{ }
shortened;

collisions =
lib.filterAttrs (_: v: builtins.length v > 1) grouped;
in
if collisions != { } then
throw ''
render-host-network: collision detected after shortening

${builtins.toJSON collisions}
''
else
builtins.listToAttrs (
map (entry: {
name = entry.original;
value = entry.rendered;
}) shortened
);

sortedAttrNames = attrs:
lib.sort builtins.lessThan (builtins.attrNames attrs);

deploymentHosts =
if inventory ? deployment
&& builtins.isAttrs inventory.deployment
&& inventory.deployment ? hosts
&& builtins.isAttrs inventory.deployment.hosts
then
inventory.deployment.hosts
else
throw "lib/render-host-network.nix: inventory.deployment.hosts missing";

deploymentHost =
if builtins.hasAttr hostName deploymentHosts
&& builtins.isAttrs deploymentHosts.${hostName}
then
deploymentHosts.${hostName}
else
throw "lib/render-host-network.nix: deployment host '${hostName}' missing";

uplinks =
if deploymentHost ? uplinks && builtins.isAttrs deploymentHost.uplinks then
deploymentHost.uplinks
else
{ };

uplinkBridgeNames =
lib.unique (
lib.filter
builtins.isString
(map
(uplinkName:
let uplink = uplinks.${uplinkName};
in uplink.bridge or null)
(sortedAttrNames uplinks))
);

localAttachTargets =
realizationPorts.attachTargetsForDeploymentHost {
inventory = inventory;
deploymentHostName = hostName;
file = "lib/render-host-network.nix";
};

localAttachBridgeNames =
lib.unique (map (target: target.name) localAttachTargets);

bridgeNamesRaw =
lib.unique (uplinkBridgeNames ++ localAttachBridgeNames);

bridgeNameMap = ensureUnique bridgeNamesRaw;

bridgeNames =
map (n: bridgeNameMap.${n}) bridgeNamesRaw;

netdevs =
builtins.listToAttrs (
map
(bridgeName: {
name = "10-${bridgeName}";
value = {
netdevConfig = {
Name = bridgeName;
Kind = "bridge";
};
};
})
bridgeNames
);

parentNetworks =
builtins.listToAttrs (
lib.filter
(entry: entry != null)
(map
(uplinkName:
let
uplink = uplinks.${uplinkName};
parent = uplink.parent or null;
bridge = uplink.bridge or null;
renderedBridge =
if builtins.isString bridge && builtins.hasAttr bridge bridgeNameMap then
bridgeNameMap.${bridge}
else
null;
in
if builtins.isString parent && renderedBridge != null then
{
name = "20-${parent}";
value = {
matchConfig.Name = parent;
networkConfig = {
Bridge = renderedBridge;
ConfigureWithoutCarrier = true;
};
};
}
else
null)
(sortedAttrNames uplinks))
);

bridgeNetworks =
builtins.listToAttrs (
map
(bridgeName: {
name = "30-${bridgeName}";
value = {
matchConfig.Name = bridgeName;
networkConfig = {
ConfigureWithoutCarrier = true;
};
};
})
bridgeNames
);

tenantRendered =
tenantBridgeRenderer.renderTenantBridges {
tenantBridges = { };
shorten = shorten;
ensureUnique = ensureUnique;
};
in
{
inherit netdevs;
networks =
parentNetworks
// bridgeNetworks
// tenantRendered.networks;
}
