{
  lib,
  pkgs,
  renderedHostNetwork ? null,
  ...
}:

let
  validationPlan = import ./host-validation/plan.nix {
    inherit lib renderedHostNetwork;
  };

  validationScript = import ./host-validation/loop.nix {
    inherit lib pkgs;
  };

  validationStatus = import ./host-validation/status.nix {
    inherit pkgs;
  };
in
{
  environment.etc."s88-network-validation/plan.json".text = builtins.toJSON validationPlan;

  environment.systemPackages = [ validationStatus ];

  systemd.services.s88-network-validation = {
    description = "Continuously validate rendered containers for DNS and IP readiness";
    wantedBy = [ "multi-user.target" ];
    after = [
      "systemd-networkd.service"
      "machines.target"
    ];
    wants = [
      "systemd-networkd.service"
      "machines.target"
    ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 2;
    };
    script = ''
      exec ${validationScript}
    '';
  };
}
