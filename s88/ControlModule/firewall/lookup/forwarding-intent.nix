{
  lib,
  runtimeTarget ? { },
  interfaces ? { },
  wanIfs ? [ ],
  lanIfs ? [ ],
  uplinks ? { },
}:

let
  common = import ./forwarding-intent/common.nix { inherit lib; };
  inherit (common) firstAttrsFromPaths boolLikeFromPaths;

  ifaceView = import ./forwarding-intent/interfaces.nix {
    inherit lib common interfaces;
  };

  nodeForwarding = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [ [ "forwarding" ] [ "forwardingIntent" ] [ "routing" ] [ "semantic" "forwarding" ] [ "semanticIntent" "forwarding" ] ];
  };

  nodeEgress = firstAttrsFromPaths {
    roots = [ runtimeTarget nodeForwarding ];
    paths = [ [ "egress" ] [ "semantic" "egress" ] [ "semanticIntent" "egress" ] ];
  };

  nodeNat = firstAttrsFromPaths {
    roots = [ runtimeTarget ];
    paths = [ [ "natIntent" ] [ "nat" ] [ "egress" "natIntent" ] [ "egress" "nat" ] ];
  };

  nodeForwardingEnabled = boolLikeFromPaths {
    roots = [ runtimeTarget nodeForwarding ];
    paths = [ [ "forwardingEnabled" ] [ "enabled" ] [ "authority" ] [ "routingAuthority" ] [ "forwardingAuthority" ] [ "forwardingResponsibility" ] [ "participatesInForwarding" ] [ "forwarding" "enabled" ] ];
  };

  egressAuthority = boolLikeFromPaths {
    roots = [ runtimeTarget nodeForwarding nodeEgress ];
    paths = [ [ "egressAuthority" ] [ "exitAuthority" ] [ "upstreamSelectionAuthority" ] [ "authority" ] [ "egress" "authority" ] ];
  };

  natEnabled = boolLikeFromPaths {
    roots = [ runtimeTarget nodeForwarding nodeEgress nodeNat ];
    paths = [ [ "enabled" ] [ "natEnabled" ] [ "nat" ] [ "nat" "enable" ] [ "masquerade" ] [ "masquerade" "enable" ] [ "egress" "nat" ] [ "egress" "nat" "enable" ] [ "egress" "masquerade" ] [ "egress" "masquerade" "enable" ] ];
  };

  roles = import ./forwarding-intent/roles.nix {
    inherit lib common runtimeTarget nodeForwarding nodeEgress nodeNat wanIfs lanIfs;
    entries = ifaceView.interfaceEntries;
    inherit (ifaceView) resolveInterfaceTokens;
  };

  normalizedExplicitForwardPairs = import ./forwarding-intent/explicit-pairs.nix {
    inherit lib common runtimeTarget nodeForwarding;
    inherit (ifaceView) resolveInterfaceTokens;
  };

  final = import ./forwarding-intent/final.nix {
    inherit lib roles normalizedExplicitForwardPairs nodeForwarding nodeForwardingEnabled natEnabled;
  };

  _uplinks = uplinks;
in
{
  inherit
    nodeForwardingEnabled
    egressAuthority
    natEnabled
    normalizedExplicitForwardPairs
    ;
  inherit (ifaceView) interfaceEntries interfaceNames;
  inherit (roles)
    explicitLocalAdapterNames
    explicitUplinkNames
    explicitTransitNames
    explicitWanNames
    explicitExitEligibleNames
    explicitNatInterfaces
    explicitClampMssInterfaces
    resolvedLocalAdapterNames
    resolvedUplinkNames
    resolvedAccessUplinkNames
    resolvedTransitNames
    resolvedWanNames
    resolvedLanNames
    ;
  inherit (final)
    accessForwardPairs
    coreForwardPairs
    upstreamSelectorForwardPairs
    coreNatInterfaces
    accessClampMssInterfaces
    coreClampMssInterfaces
    authoritativeAccessForwarding
    authoritativeCoreForwarding
    authoritativeCoreNat
    authoritativeUpstreamSelectorForwarding
    ;
}
