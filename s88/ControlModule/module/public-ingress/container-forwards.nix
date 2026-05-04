{ lib }:

let
  attrOr = value: if builtins.isAttrs value then value else { };
  listOr = value: if builtins.isList value then value else [ ];
  strOrNull = value: if builtins.isString value && value != "" then value else null;

  requiredString = path: value:
    let
      stringValue = strOrNull value;
    in
    if stringValue == null then
      throw "network-renderer-nixos public-ingress: ${path} is required"
    else
      stringValue;

  nftString = value: ''"${lib.replaceStrings [ ''\'' "\\" ''"'' ] [ ''\\'' "\\\\" ''\"'' ] (toString value)}"'';

  protocolDportRule = ifaceName: proto: port:
    ''insert rule inet router input iifname ${nftString ifaceName} meta l4proto ${proto} ${proto} dport ${toString port} accept comment "s88-public-runtime-input"'';

  protocolRules = ifaceName: protocols: ports:
    lib.concatMapStringsSep "\n"
      (proto:
        lib.concatMapStringsSep "\n"
          (port: protocolDportRule ifaceName proto port)
          ports)
      protocols;

  moduleForForward = forward:
    let
      container = attrOr (forward.containerInterface or { });
      containerName = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].containerInterface.container" (
        container.container or null
      );
      interfaceName = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].containerInterface.name" (
        container.name or null
      );
      hostBridge = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].containerInterface.hostBridge" (
        container.hostBridge or null
      );
      localAddress = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].containerInterface.localAddress" (
        container.localAddress or null
      );
      gateway4 = requiredString "runtimeFacts.publicIngress.runtimeForwards[*].containerInterface.gateway4" (
        container.gateway4 or null
      );
      protocols = if listOr (forward.protocols or null) == [ ] then [ "tcp" "udp" ] else forward.protocols;
      inputDports = listOr (container.inputDports or forward.inputDports or [ ]);
      routeMetric = container.routeMetric or 5000;
      inputRules =
        if inputDports == [ ] then
          ""
        else
          protocolRules interfaceName protocols inputDports;
    in
    {
      ${containerName} = {
        extraVeths.${interfaceName} = {
          inherit hostBridge localAddress;
        };
        config = { lib, ... }: {
          systemd.network.networks."10-${interfaceName}" = lib.mkForce {
            matchConfig.Name = interfaceName;
            networkConfig = {
              DHCP = "no";
              IPv6AcceptRA = false;
            };
            address = [ localAddress ];
            routes = [
              {
                Gateway = gateway4;
                Metric = routeMetric;
              }
            ];
          };
          boot.kernel.sysctl = {
            "net.ipv4.conf.all.rp_filter" = lib.mkForce 0;
            "net.ipv4.conf.default.rp_filter" = lib.mkForce 0;
            "net.ipv4.conf.${interfaceName}.rp_filter" = lib.mkForce 0;
          };
          networking.firewall.checkReversePath = lib.mkForce false;
          networking.nftables.ruleset = lib.mkAfter inputRules;
        };
      };
    };

  hasContainerInterface = forward: builtins.isAttrs (forward.containerInterface or null);
in
runtimeForwards:
lib.foldl' lib.recursiveUpdate { } (map moduleForForward (builtins.filter hasContainerInterface runtimeForwards))
