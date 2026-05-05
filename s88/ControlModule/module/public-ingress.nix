{
  lib,
  pkgs ? null,
  controlPlane,
  inventory,
  hostName,
  runtimeFacts ? { },
}:

let
  facts = import ./public-ingress/facts.nix { inherit lib; };
  rules = import ./public-ingress/rules.nix { inherit lib; };
  containerForwards = import ./public-ingress/container-forwards.nix { inherit lib; };
  hostRoutes = import ./public-ingress/host-routes.nix { inherit lib; };

  inherit (facts) attrOr listOr requiredString cpmDataFrom serviceIngressesFor runtimeForwardsFor;
  inherit (rules)
    nftString
    renderServiceForward
    renderServiceAccept
    renderRuntimeForward
    renderRuntimeAccept
    ;

  cpmRoot = cpmDataFrom controlPlane;
  inventoryRoot = attrOr inventory;
  host = attrOr (((attrOr (inventoryRoot.deployment or { })).hosts or { }).${hostName} or { });
  publicIngressFacts = attrOr (runtimeFacts.publicIngress or { });
  enabled = publicIngressFacts != { };

  bridgeInterface =
    if builtins.isString (publicIngressFacts.bridgeInterface or null) then
      publicIngressFacts.bridgeInterface
    else
      requiredString "inventory.deployment.hosts.${hostName}.wanUplink bridge" (
        let
          wanUplink = host.wanUplink or null;
          uplinks = attrOr (host.uplinks or { });
        in
        if wanUplink != null && builtins.isAttrs (uplinks.${wanUplink} or null) then
          uplinks.${wanUplink}.bridge or null
        else
          null
      );

  snatSourceCidr4 = requiredString "runtimeFacts.publicIngress.snatSourceCidr4" (
    publicIngressFacts.snatSourceCidr4 or null
  );

  serviceIngresses = serviceIngressesFor { inherit cpmRoot publicIngressFacts; };
  runtimeForwards = runtimeForwardsFor { inherit cpmRoot publicIngressFacts; };
  dynamicPublicIPv4Bindings =
    lib.filter
      (forward: builtins.isString (forward.publicIPv4SecretPath or null) && builtins.isString (forward.publicIPv4SetName or null))
      (serviceIngresses ++ runtimeForwards);
  dynamicPublicIPv4Sets =
    lib.concatMapStringsSep "\n"
      (forward:
        ''
          set ${forward.publicIPv4SetName} {
            type ipv4_addr
            flags interval
          }
        '')
      dynamicPublicIPv4Bindings;
  dynamicPublicIPv4Loader =
    lib.concatMapStringsSep "\n"
      (forward:
        ''
          load_public_ipv4 ${nftString forward.publicIPv4SetName} ${nftString forward.publicIPv4SecretPath} ${if forward.publicIPv4AssignToBridge or false then "1" else "0"}
        '')
      dynamicPublicIPv4Bindings;
  nftBin =
    if pkgs != null then
      "${pkgs.nftables}/bin/nft"
    else
      "nft";
  trBin =
    if pkgs != null then
      "${pkgs.coreutils}/bin/tr"
    else
      "tr";
  ipBin =
    if pkgs != null then
      "${pkgs.iproute2}/bin/ip"
    else
      "ip";
  containerForwardModules = containerForwards runtimeForwards;
  bridgeNetworkName = publicIngressFacts.bridgeNetworkName or "30-${bridgeInterface}";
  routeModule = hostRoutes { inherit bridgeNetworkName serviceIngresses; };
  serviceDportsFor = proto:
    lib.unique (
      lib.concatMap
        (forward:
          lib.concatMap
            (match:
              if (match.proto or "any") == proto then
                listOr (match.dports or null)
              else
                [ ])
            (listOr (forward.matches or null)))
        serviceIngresses
    );
  protectedDportsByProto = {
    tcp = serviceDportsFor "tcp";
    udp = serviceDportsFor "udp";
  };

  preroutingRules =
    lib.concatStringsSep "\n" (
      (map (renderServiceForward bridgeInterface) serviceIngresses)
      ++ (map (renderRuntimeForward bridgeInterface requiredString protectedDportsByProto) runtimeForwards)
    );
  forwardRules =
    lib.concatStringsSep "\n" (
      (map (renderServiceAccept bridgeInterface) serviceIngresses)
      ++ (map (renderRuntimeAccept bridgeInterface requiredString) runtimeForwards)
    );
in
if !enabled then
  { }
else
  lib.recursiveUpdate {
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkForce true;
    containers = containerForwardModules;
    systemd.network.networks = (routeModule.systemd.network.networks or { });
    networking.nftables.enable = true;
    networking.nftables.ruleset = ''
      table inet s88_host_public_ingress {
${dynamicPublicIPv4Sets}

        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
${preroutingRules}
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${snatSourceCidr4} oifname != ${nftString bridgeInterface} masquerade comment "s88-host-public-ingress-snat"
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          iifname ${nftString bridgeInterface} oifname != ${nftString bridgeInterface} accept comment "s88-host-public-ingress-egress"
          iifname != ${nftString bridgeInterface} oifname ${nftString bridgeInterface} ct state established,related accept comment "s88-host-public-ingress-return"
${forwardRules}
        }
      }
    '';
  }
  (lib.optionalAttrs (dynamicPublicIPv4Bindings != [ ]) {
    systemd.services.s88-host-public-ingress-runtime-addresses = {
      description = "Load runtime public ingress IPv4 nft sets";
      wantedBy = [ "multi-user.target" ];
      after = [
        "nftables.service"
        "sops-nix.service"
      ];
      wants = [ "nftables.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail

        load_public_ipv4() {
          set_name="$1"
          secret_path="$2"
          assign_to_bridge="$3"
          if [ ! -s "$secret_path" ]; then
            echo "s88-host-public-ingress: missing runtime IPv4 secret $secret_path for nft set $set_name" >&2
            exit 1
          fi
          value="$(${trBin} -d '[:space:]' <"$secret_path")"
          if [ -z "$value" ]; then
            echo "s88-host-public-ingress: empty runtime IPv4 secret $secret_path for nft set $set_name" >&2
            exit 1
          fi
          if [ "$assign_to_bridge" = "1" ]; then
            ${ipBin} addr replace "$value/32" dev ${nftString bridgeInterface}
          fi
          ${nftBin} flush set inet s88_host_public_ingress "$set_name"
          ${nftBin} add element inet s88_host_public_ingress "$set_name" "{ $value }"
        }

${dynamicPublicIPv4Loader}
      '';
    };
  })
