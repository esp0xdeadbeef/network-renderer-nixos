# Regression Notes

Keep this file current with solved or intentionally accepted repository-local
test-gate findings. Unresolved implementation defects should name the failing
command, evidence, owner, and next fix.

- `s88/ControlModule/render/container-networks/interface-units.nix`: ACCEPTED OVER-LIMIT. Single responsibility: emits container interface systemd network units from explicit runtime interface records. Splitting would scatter shared ordering and naming invariants across smaller files.
- `s88/ControlModule/render/container-networks/policy-routing/raw-routes.nix`: ACCEPTED OVER-LIMIT. Single responsibility: normalizes raw policy-route records for renderer emission. Splitting would separate common validation from route-shape handling.
