args@{ lib
, repoPath
, hostName
, cpm
, inventory ? { }
, hostContext ? null
,
}:

import ./host-plan/default.nix args
