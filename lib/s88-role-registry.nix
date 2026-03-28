{ lib }:

{
  access = {
    runtimeRole = "access";
    hostProfilePath = null;
    container = {
      enable = true;
      profilePath = ../s88/CM/network/profiles/access.nix;
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
      profilePath = ../s88/CM/network/profiles/core.nix;
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
      profilePath = ../s88/CM/network/profiles/policy.nix;
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
      profilePath = ../s88/CM/network/profiles/upstream-selector.nix;
      additionalCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };
}
