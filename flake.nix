{
  description = "System Configuration(s)";

  inputs = {
    nixos.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    impermanence.url = "github:nix-community/impermanence";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixos";
      # flake = false;
    };
    vscode-server-patch = {
      url = "github:msteen/nixos-vscode-server/master";
      flake = false;
    };
    nix-matlab = {
      url = "gitlab:doronbehar/nix-matlab/master";
      inputs.nixpkgs.follows = "nixos";
    };
    argononed = {
      url = "gitlab:ykis-0-0/argononed/feat/nixos";
      flake = false;
    };
    # secret-wrapper: to be supplied on target hosts
  };

  outputs = { self, secret-wrapper ? null, ... }@inputs: {
    nixosConfigurations = {
      rpinix = inputs.nixos.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = builtins.removeAttrs inputs [ "self" "nix-matlab" ];
        modules = [
          ./expectations/flakes.nix
          ./raspberrypi/configuration.nix
          ./expectations/passwdmgr/default.nix
          ./raspberrypi/hardware.nix
          ./raspberrypi/storage.nix
          ./expectations/argononed.nix
        ];
      };

      vbox = inputs.nixos.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = builtins.removeAttrs inputs [ "self" "vscode-server-patch" "argononed" ];
        modules = [
          ./expectations/flakes.nix
          ./virtualbox/configuration.nix
          ./virtualbox/hardware.nix
          ./virtualbox/storage.nix
          # ./expectations/pipewire.nix
          ./expectations/gui/awesome.nix
        ];
      };
    };

    devShells = let
      # Copied from https://github.com/nix-community/home-manager/blob/master/flake.nix#L6
      #
      # List of systems supported by home-manager binary (NixOS only in our case)
      supportedSystems = builtins.attrNames inputs.nixos.legacyPackages; # inputs.nixos.lib.platforms.linux;

      # Function to generate a set based on supported systems
      forAllSystems = f:
        inputs.nixos.lib.genAttrs supportedSystems (system: f system);

      callArg = system: {
        pkgs = inputs.nixos.legacyPackages.${system};
      };
    in forAllSystems (system: {
      hm-install = (import "${inputs.home-manager}" (callArg system)).install;
    });


    homeConfigurations = let
      _mkHomeConfig = inputs.home-manager.lib.homeManagerConfiguration;
      mkHomeConfig = {
        username, host,
        profileName ? "${username}@${host}", homeDirectory ? "/home/${username}",
        ...
      }@args: {
        name = profileName;
        value = _mkHomeConfig ((builtins.removeAttrs args ["host"]) // {
          inherit homeDirectory; # To force realiastion?
          system = self.nixosConfigurations.${host}.pkgs.system;
        });
      };
      mkHomeConfigurations = builders: builtins.listToAttrs (map mkHomeConfig builders);
    in mkHomeConfigurations [
      {
        username = "nixos";
        host = "vbox";
        stateVersion = "22.05";
        configuration = import ./home-manager/nixos/vbox.host.nix;
        extraSpecialArgs = {
          inherit (inputs) nix-matlab;
        };
      }
      {
        username = "nixos";
        host = "rpinix";
        stateVersion = "22.05";
        configuration = import ./home-manager/nixos/rpinix.host.nix;
        extraSpecialArgs = {
          vscode-srv = inputs.vscode-server-patch;
        };
      }
    ];

  };
}
