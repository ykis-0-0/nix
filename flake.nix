{
  description = "System Configuration(s)";

  inputs = {
    # region (Semi-)Endorsed Modules
    nixos.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixos";
    };
    impermanence.url = "github:nix-community/impermanence";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixos";
      # flake = false;
    };
    # endregion
    # region Thrid-party Modules
    vscode-server-patch = {
      url = "github:msteen/nixos-vscode-server/master";
      flake = false;
    };
    nix-matlab = {
      url = "gitlab:doronbehar/nix-matlab/master";
      inputs.nixpkgs.follows = "nixos";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixos";
    };
    # endregion
    # region Homebrew
    argononed = {
      url = "gitlab:DarkElvenAngel/argononed/master";
      flake = false;
    };
    npiperelay = {
      url = "github:ykis-0-0/npiperelay.nix";
      inputs.nixpkgs.follows = "nixos";
    };
    # secret-wrapper: to be supplied on target hosts
    secret-wrapper.follows = "";
    sched-reboot = {
      url = "./modules/sched-reboot";
      inputs.nixpkgs.follows = "nixos";
    };
    # endregion
  };

  outputs = { self, secret-wrapper ? null, ... }@inputs: {
    nixosConfigurations = let
      nixosConfigurations' = import ./nixos/systems.nix inputs;
      createSystem = inputs.nixos.lib.nixosSystem;
      mapper = host: config: createSystem {
        inherit (config) system modules;
        specialArgs = let
          inherit (builtins) removeAttrs filter attrNames elem;
          inherit (config) includeInputs;
        in
          removeAttrs inputs (filter (input: ! elem input includeInputs) (attrNames inputs));
      };
    in builtins.mapAttrs mapper nixosConfigurations';

    # OS Images are removed as none of them works in their current form
    # packages = {};

    homeConfigurations = let
      mkHomeConfig_ = inputs.home-manager.lib.homeManagerConfiguration;
      mkHomeConfig' = {
        username, host,
        profileName ? "${username}@${host}", homeDirectory ? "/home/${username}",
        # Upstream args
        modules, extraSpecialArgs
      }@args: {
        name = profileName;
        value = mkHomeConfig_ {
          pkgs = self.nixosConfigurations.${host}.pkgs;
          modules = [{
            home = {
              inherit username homeDirectory;
            };
          }] ++ modules;
          inherit extraSpecialArgs;
        };
      };
      mkHomeConfigurations = builders: builtins.listToAttrs (map mkHomeConfig' builders);
      homeConfigurations' = import ./nixos/homes.nix (let
          getSystem = name: conf: conf.pkgs.stdenv.hostPlatform.system;
        in inputs // {
          systems' = builtins.mapAttrs getSystem self.nixosConfigurations;
        }
      );
    in mkHomeConfigurations homeConfigurations';

    deploy.nodes = import ./nixos/deployments.nix inputs;
  };
}
