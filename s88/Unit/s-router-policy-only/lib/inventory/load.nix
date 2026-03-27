{ inventory }:

if !builtins.isAttrs inventory then
  abort "renderer: inventory must be an attribute set"
else if !(inventory ? deployment) then
  abort "renderer: inventory.deployment is missing"
else if !(inventory.deployment ? hosts) then
  abort "renderer: inventory.deployment.hosts is missing"
else if !(inventory ? realization) then
  abort "renderer: inventory.realization is missing"
else if !(inventory.realization ? nodes) then
  abort "renderer: inventory.realization.nodes is missing"
else
  inventory
