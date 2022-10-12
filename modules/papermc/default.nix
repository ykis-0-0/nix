{ config, lib, pkgs, ... }:{
  options.services.papermc = let
    inherit (lib) types mkOption mkEnableOption mkPackageOption;
  in {
    enable = mkEnableOption "the PaperMC Minecraft dedicated server";
    systemd-verbose = mkEnableOption "logging PaperMC console output to Systemd Journal (for debugging purposes only)";

    port = mkOption {
      type = types.port;
      default = 25565;
      description = "TCP & UDP port for PaperMC to bind against";
    };

    memory = let
      mkMemOpt = valType: defVal: mkOption {
        type = types.ints.positive;
        default = defVal;
        description = "${valType} size of the JVM Heap, in MiB";
      };
    in {
      min = mkMemOpt "Minimum" 1024;
      max = mkMemOpt "Maximum" 4096;
    };

    packages = {
      jre = mkPackageOption pkgs "JRE" { default = [ "temurin-jre-bin" ]; };

      papermc = {
        version = mkOption {
          type = types.str;
          description = "Minecraft version to run PaperMC on";
        };
        build = mkOption {
          type = types.nullOr types.ints.unsigned;
          default = null;
          description = "PaperMC build to pin against, or `null` to use latest";
        };
      };
    };

    storages = let
      mkStorageOpt = key: type: mkOption {
        type = types.path;
        description = "Location of ${type} for PaperMC";
      };
    in builtins.mapAttrs mkStorageOpt {
      # srv-root = "Server root directory"; # FIXME think again of whether really include it
      bin = "binaries";
      etc = "configuration files";
      worlds = "world saves";
      log = "logs";
      plugins = "plugins";
      cache = "binary cache";
    };

    cliArgs = {
      jvm = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra arguments to specify for the JVM when launching the server.\
          `-Xmx` and `-Xms` should be set via `services.papermc.memory`.\
          Multiple definitions will be merged in an unknown order.
        '';
      };

      papermc = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra arguments to specify for PaperMC itself when launching the server.\
          Multiple definitions will be merged in an unknown order.
        '';
      };
    };
  };

  config = let
    selfCfg = config.services.papermc;
    papermc-scripts = pkgs.stdenvNoCC.mkDerivation {
      name = "systemd-papermc-utils";
      src = ./scripts;

      # dontUnpack = true;
      dontPatch = true;
      dontConfigure = true;
      dontBuild = true;
      # dontInstall = true;
      installPhase = ''
        mkdir "$out"
        install -m 0755 -t "$out" ./*
      '';
      # dontFixup = true;
    };
  in lib.mkIf selfCfg.enable {
    systemd = {
      services = {
        papermc = {
          enable = true;
          description = "PaperMC Minecraft dedicated server Instance";

          path = with pkgs; [
            wget jq # required by ./update_check.sh
            abduco selfCfg.packages.jre # required by ./bootstrap.sh
          ];
          environment = {
            MINECRAFT_VERSION = selfCfg.packages.papermc.version;
            PAPER_BUILD = toString selfCfg.packages.papermc.build; # builtins.toString will map null to ""
            BIN_DIR = let
              inherit (config.systemd.services.papermc.serviceConfig) RuntimeDirectory;
            in "/run/${RuntimeDirectory}/bin/"; # toString selfCfg.storages.bin;

            TZ = config.time.timeZone;
          };

          serviceConfig = let
            folders = builtins.mapAttrs (_: builtins.toString) selfCfg.storages;
            memory = builtins.mapAttrs (_: builtins.toString) selfCfg.memory;
          in let
            RuntimeDirectory = "ykis/papermc";
          in{
            Type = if selfCfg.systemd-verbose then "simple" else "forking";
            Restart = "no";

            inherit RuntimeDirectory;
            RuntimeDirectoryPreserve = "restart";
            BindPaths = [
              "${folders.bin}/:/run/${RuntimeDirectory}/bin/"
              "${folders.plugins}/:/run/${RuntimeDirectory}/plugins/"
              "${folders.worlds}/:/run/${RuntimeDirectory}/worlds/"
              "${folders.etc}/:/run/${RuntimeDirectory}/etc/"
              "${folders.log}/:/run/${RuntimeDirectory}/etc/logs/"
              "${folders.cache}/:/run/${RuntimeDirectory}/etc/cache/"
            ];
            WorkingDirectory = "/run/${RuntimeDirectory}/etc";

            ExecStartPre = "${papermc-scripts}/updater.sh";
            ExecStart = let
              argsFile = pkgs.writeText "papermc-jvm-args" ''
                -Xms${memory.min}M
                -Xmx${memory.max}M

                # Extra JVM Options
                ${selfCfg.cliArgs.jvm}
                # End JVM Extra Options

                -jar /run/${RuntimeDirectory}/bin/paper.jar
                --nogui
                --world-container /run/${RuntimeDirectory}/worlds/
                --plugins /run/${RuntimeDirectory}/plugins/
                --port ${toString selfCfg.port}

                # Extra PaperMC Options
                ${selfCfg.cliArgs.papermc}
                # End PaperMC Extra Options
              '';
            in
              "${papermc-scripts}/bootstrapper.sh ${if selfCfg.systemd-verbose then "relay" else "launch"} /run/${RuntimeDirectory}/abduco.sock ${selfCfg.packages.jre}/bin/java @${argsFile}";
          };
        };

        # TODO Discord Webhook notifier service definition
        discord-prophet = {};

        # TODO BorgBase backup service definition
        borgbase-mcbackup = {};
      };

      timers.sched-reboot.conflicts = [ "papermc.service" ];
    };
  };

  /*
    HACK Thing to be designed in regard to the  minecraft server infrastructure
    - Main Server Instance
      1. How should the connection between the binary and systemd be established? dtach / abduco?
      2. Should the updater be put at ExecPreStart?
    - BorgBase backup runner
      1. How often should the runner be triggered?
      2. And from which side (systemd / instance)?
        a. If we use systemd, how should we instruct the instance to not touch the save / make a local snapshot?
    - Discord Webhook postman
      1. How should we trigger the webhook? (systemd / instance)?
  */
}