{
  description = "OpenTofu + GitHub provider for n-at-han-k's funding config";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            (pkgs.opentofu.withPlugins (p: [ p.integrations_github ]))
            # The README renderer is plain stdlib YAML, but the shell should
            # be able to run it and the registry checks without a system Ruby.
            pkgs.ruby_3_4
          ];
        };
      }
    );
}
