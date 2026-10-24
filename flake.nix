{
  description = "nixbook-elite: a Chromebook-like, secure and private NixOS for the HP EliteBook 840 G10";

  inputs = {
    # Stable base (NixOS 26.05) with the 6.18 LTS kernel
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only used for fast moving tools: AI CLIs, Bazaar, NordVPN and GNOME extensions
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/latest";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      lanzaboote,
      disko,
      nix-flatpak,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      specialArgs = { inherit inputs pkgs-unstable; };

      nixbook = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          lanzaboote.nixosModules.lanzaboote
          disko.nixosModules.disko
          nix-flatpak.nixosModules.nix-flatpak
          ./hosts/elitebook
        ];
      };

      installer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = specialArgs // {
          targetSystem = nixbook;
          flakeSource = self;
        };
        modules = [ ./installer/iso.nix ];
      };
    in
    {
      nixosConfigurations = {
        inherit nixbook installer;
      };

      packages.${system} = {
        default = installer.config.system.build.isoImage;
        iso = installer.config.system.build.isoImage;
        toplevel = nixbook.config.system.build.toplevel;
      };

      checks.${system} = {
        install = import ./tests/install.nix {
          inherit pkgs lib nixbook;
          flakeSource = self;
        };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
