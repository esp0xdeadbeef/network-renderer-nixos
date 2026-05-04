{
  lib,
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

  inherit (facts) attrOr requiredString cpmDataFrom serviceIngressesFor runtimeForwardsFor;
  inherit (rules) nftString renderServiceForward renderServiceAccept renderRuntimeForward renderRuntimeAccept;

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
  containerForwardModules = containerForwards runtimeForwards;
  bridgeNetworkName = publicIngressFacts.bridgeNetworkName or "30-${bridgeInterface}";
  routeModule = hostRoutes { inherit bridgeNetworkName serviceIngresses; };

  preroutingRules =
    lib.concatStringsSep "\n" (
      (map (renderServiceForward bridgeInterface) serviceIngresses)
      ++ (map (renderRuntimeForward bridgeInterface requiredString) runtimeForwards)
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
  {
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkForce true;
    containers = containerForwardModules;
    systemd.network.networks = (routeModule.systemd.network.networks or { });
    networking.nftables.enable = true;
    networking.nftables.ruleset = ''
      table inet s88_host_public_ingress {
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
