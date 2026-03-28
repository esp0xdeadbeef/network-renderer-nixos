{ lib }:

let
selectors = import ./host-query.nix { inherit lib; };
realizationPorts = import ./realization-ports.nix { inherit lib; };
in
{
inherit realizationPorts selectors;

renderer = {
loadIntent = selectors.importMaybeFunction;
loadInventory = selectors.importMaybeFunction;

renderHostNetwork =
{
inventory,
hostName,
cpm ? null,
}:
import ./render-host-network.nix {
inherit lib inventory hostName cpm;
};
};
}
