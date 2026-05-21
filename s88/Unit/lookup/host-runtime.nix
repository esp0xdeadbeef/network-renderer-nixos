args@{ lib
, repoPath
, hostName
, cpm
, inventory ? { }
, hostContext ? null
,
}:

import ./host-runtime/default.nix args
