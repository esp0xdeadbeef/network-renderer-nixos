{
  lib,
  containerModel,
}:

let
  loopback = containerModel.loopback or { };

  loopbackAddresses = lib.filter builtins.isString [
    (loopback.addr4 or null)
    (loopback.addr6 or null)
  ];
in
{
  loopbackUnit = lib.optionalAttrs (loopbackAddresses != [ ]) {
    "00-lo" = {
      matchConfig.Name = "lo";
      address = loopbackAddresses;
      linkConfig.RequiredForOnline = "no";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };
}
