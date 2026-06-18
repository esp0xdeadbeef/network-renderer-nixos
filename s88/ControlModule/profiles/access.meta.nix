{
  container = {
    enable = true;
    advertise = {
      dhcp4 = true;
      radvd = true;
    };
    enableEdgeServices = true;
  };
  assumptionFamily = "edge";
}
