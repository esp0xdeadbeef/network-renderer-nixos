args@{ lib
, hostName
, deploymentHostName
, deploymentHost
, renderHostConfig
, cpm
, source ? { }
, attachTargetsBase
,
}:

import ./wan-attachment/default.nix args
