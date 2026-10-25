{
  lib,
  pkgs,
  containerName,
  renderedModel,
  alarmModel,
}:

let
  debugTools = import ../../../debug-tools.nix { inherit pkgs; };
  usesExtraVeths = builtins.attrNames (renderedModel.veths or { }) != [ ];
in
{
  imports = lib.optionals (renderedModel ? profilePath && renderedModel.profilePath != null) [
    renderedModel.profilePath
  ];

  resolvedHostName =
    if renderedModel ? unitName && builtins.isString renderedModel.unitName then
      renderedModel.unitName
    else
      containerName;

  warningMessages =
    if alarmModel ? warningMessages && builtins.isList alarmModel.warningMessages then
      lib.unique (lib.filter builtins.isString alarmModel.warningMessages)
    else
      [ ];

  commonRouterConfig = {
    boot.isContainer = true;
    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.services.systemd-networkd-wait-online.enable = lib.mkIf usesExtraVeths (lib.mkForce false);
    networking.useDHCP = false;
    networking.networkmanager.enable = lib.mkDefault false;
    networking.useHostResolvConf = false;
    services.resolved.enable = lib.mkDefault false;
    networking.firewall.enable = false;

    # Router containers never build, substitute, or garbage-collect Nix
    # packages: their entire closure is supplied by the host, which mounts it
    # read-only through the container's nix store bind. Leaving `nix.enable` on
    # gave every one of the modelled scopes its own `nix-daemon` socket, plus a
    # `nix-gc` timer and a `nix-optimise` timer, so a 15-container router ran
    # ~45 pointless services and paid their start cost on every boot. Disabling
    # it removes the daemon and both timers outright.
    #
    # This is a mechanised cleanup with no network meaning (FS-171: realization
    # mechanics may not create or alter modelled behaviour). It removes nothing
    # the model declared: no route, firewall rule, DNS, NAT/NAT66, overlay, or
    # service exposure is affected, because none of those are produced by a
    # local nix daemon.
    nix.enable = false;

    # Docs are unreachable inside a router container and dominate build time
    # for modules that would otherwise pull them in.
    documentation.enable = false;
    documentation.man.enable = false;
    documentation.doc.enable = false;
    documentation.info.enable = false;

    # NOTE: `services.nscd` is deliberately left enabled. nixpkgs documents
    # that disabling it "effectively disables NSS Lookups from all non-glibc
    # NSS modules, including the ones provided by systemd", so turning it off
    # would trade a small boot saving for broken user/group resolution inside
    # the router containers. The nix daemon and both timer units above are the
    # safe part of the win.

    environment.systemPackages = debugTools;
    system.stateVersion = "25.11";
  };
}
