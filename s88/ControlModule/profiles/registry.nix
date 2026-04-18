{ lib }:

{
  access = {
    runtimeRole = "access";
    hostProfilePath = null;
    container = {
      enable = true;
      profilePath = ../profiles/access.nix;
      advertise = {
        dhcp4 = true;
        radvd = true;
      };
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };

  core = {
    runtimeRole = "core";
    hostProfilePath = null;
    container = {
      enable = true;
      profilePath = ../profiles/core.nix;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };

  policy = {
    runtimeRole = "policy";
    hostProfilePath = null;
    container = {
      enable = true;
      profilePath = ../profiles/policy.nix;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };

  upstream-selector = {
    runtimeRole = "upstream-selector";
    hostProfilePath = null;
    container = {
      enable = true;
      profilePath = ../profiles/upstream-selector.nix;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };

  downstream-selector = {
    runtimeRole = "downstream-selector";
    hostProfilePath = null;
    container = {
      enable = true;
      profilePath = ../profiles/upstream-selector.nix;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };
}
