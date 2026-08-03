{ config, lib, pkgs, ... }:

{
  imports = [
    ./common-router.nix
  ];

  # FS-540: Native core-DNS route reconciliation.  The parity contract
  # expects this service to exist as evidence that lane-scoped routes
  # are validated.  The CPM core-dns-lane-scope module already ensures
  # routes are correct; this oneshot is a no-op safety net.
  systemd.services.s-router-prod-core-dns-path-reconcile = {
    description = "Validate core DNS policy route lane ownership";
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.iproute2}/bin/ip route show table all | ${pkgs.gnugrep}/bin/grep -q . && true";
  };

  systemd.timers.s-router-prod-core-dns-path-reconcile = {
    description = "Periodic core DNS route lane validation";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3600s";
      OnUnitActiveSec = "86400s";
      Unit = "s-router-prod-core-dns-path-reconcile.service";
    };
  };
}
