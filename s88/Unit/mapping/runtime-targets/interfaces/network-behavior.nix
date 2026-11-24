{ lib }:

interfaces: runtimeTarget:

let
  facts = if builtins.isAttrs runtimeTarget then runtimeTarget.facts or { } else { };

  participation =
    let
      tp = facts.traversalParticipation or null;
    in
    if builtins.isAttrs tp then tp else { };

  published = builtins.isAttrs (facts.traversalParticipation or null);

  flag = name: (participation.${name} or false) == true;

  decision = {
    isSelector =
      flag "transit"
      && !(flag "ingress")
      && !(flag "enforcement")
      && !(flag "upstreamSelection")
      && !(flag "exit");
    isUpstreamSelector = flag "upstreamSelection";
    isPolicy = flag "enforcement";
    isAccessGateway = flag "ingress";
  };
in
decision
// {
  inherit published participation;
  keepInterfaceRoutesInMain =
    !(
      decision.isSelector || decision.isUpstreamSelector || decision.isPolicy || decision.isAccessGateway
    );
}
