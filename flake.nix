{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zuul = {
      url = "git+https://review.opendev.org/zuul/zuul";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {

    lib = {
      forAllSystems = function:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
        ] (system: function (import nixpkgs { inherit system; }));
    };
    packages = self.lib.forAllSystems (pkgs: (import ./zuul.nix {
      inherit pkgs inputs;
    }));
  };
}

