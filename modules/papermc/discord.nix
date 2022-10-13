{ config, lib, pkgs, ... }:{
  config = let
    selfCfg = config.services.papermc;
  in lib.mkIf selfCfg.enable {

    # TODO Discord Webhook notifier service definition
    systemd.services.discord-prophet = {};
  };
}
