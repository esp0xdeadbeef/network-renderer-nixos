
# network-renderer-nixos

Shared NixOS router-unit modules and renderer helpers.

## Exports

### Library

- `lib.queryBox`
- `lib.renderer.loadIntent`
- `lib.renderer.loadInventory`
- `lib.renderer.validateInventory`
- `lib.renderer.renderHostNetwork`
- `lib.renderer.renderContainers`

### Router units

- `s88.Unit.s-router-access`
- `s88.Unit.s-router-core`
- `s88.Unit.s-router-policy-only`
- `s88.Unit.s-router-upstream-selector`

### NixOS modules

- `nixosModules.s-router-access`
- `nixosModules.s-router-core`
- `nixosModules.s-router-policy-only`
- `nixosModules.s-router-upstream-selector`

## Expected renderer flow

1. load `intent.nix`
2. load `inventory.nix`
3. derive deployment host through `queryBox`
4. render host equipment from inventory
5. inspect renderer/runtime variables
6. fail clearly when required data is missing

## Dry variable dump

The repository exposes:

```bash
nix run .#render-dry-config -- /path/to/intent.nix
```
The dry dump is intentionally not a realized device config. It writes numbered JSON files
into the current working directory and prints the combined dump to the terminal.

File layout

Inputs:

00-intent.json
01-inventory.json

Derived dry-render dumps:

10-paths.json
20-query-box.json
30-rendered-hosts.json
90-dry-config.json
Batch runner

To run the dry dump across the example repository:

./render-all.sh

Or against a specific checkout/store path:

./render-all.sh /path/to/network-labs

The batch runner follows the expected TODO-style loop:

find every intent.nix
call nix run .#render-dry-config -- "$file"
on failure, dump the numbered JSON files already written
Core fabric link renderer

The core WAN container no longer hardcodes a policy-specific fabric renderer path.

Active import:

./s88/Unit/s-router-core/container-wan/network/fabric.nix

Compatibility shim retained:

./s88/Unit/s-router-core/container-wan/network/link-to-policy.nix

The shim now delegates to the generic fabric-link renderer.


