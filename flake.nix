{
  description = "NixOS network renderer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0182a361324364ae3f436a63005877674cf45efb";

    network-control-plane-model.url =
      "github:esp0xdeadbeef/network-control-plane-model";

    network-compiler.url =
      "github:esp0xdeadbeef/network-compiler";

    network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";
    network-compiler.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, network-control-plane-model, network-compiler }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.pyyaml
        ps.pandas
      ]);

      rendererScript = pkgs.writeText "generate-nixos-config.py"
        (builtins.readFile ./generate-nixos-config.py);
    in
    {
      nixosConfigurations.lab = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./vm.nix ];
      };

      packages.${system} = {
        generate-nixos-config =
          pkgs.writeShellApplication {
            name = "generate-nixos-config";

            runtimeInputs = [
              pythonEnv
              pkgs.jq
            ];

            text = ''
              set -euo pipefail

              if [ "$#" -lt 1 ]; then
                echo "Usage: $0 <input.nix> [output-dir]" >&2
                exit 1
              fi

              INPUT_NIX="$1"
              COMPILER_JSON="output-compiler-signed.json"
              SOLVER_JSON="output-solver-signed.json"
              OUTPUT_DIR="''${2:-work/nixos-output}"

              echo "[*] Running compiler..."
              nix run github:esp0xdeadbeef/network-compiler -- "$INPUT_NIX" "$COMPILER_JSON"

              echo "[*] Running solver..."
              nix run github:esp0xdeadbeef/network-compiler -- "$COMPILER_JSON" "$SOLVER_JSON"

              echo "[*] Validating JSON..."
              jq empty "$SOLVER_JSON"

              echo "[*] Generating NixOS modules..."

              export PYTHONPYCACHEPREFIX=/tmp/python-cache
              export PYTHONDONTWRITEBYTECODE=1
              PYTHONPATH="$(pwd)" \
              ${pythonEnv}/bin/python3 ${rendererScript} \
                "$SOLVER_JSON" \
                --output-dir "$OUTPUT_DIR"
            '';
          };

        default = self.packages.${system}.generate-nixos-config;
      };

      apps.${system} = {
        generate-nixos-config = {
          type = "app";
          program =
            "${self.packages.${system}.generate-nixos-config}/bin/generate-nixos-config";
        };

        default = self.apps.${system}.generate-nixos-config;
      };

      defaultPackage.${system} =
        self.packages.${system}.generate-nixos-config;
    };
}
