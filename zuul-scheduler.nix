{ inputs }:
{ config, pkgs, lib, ... }: let
  cfg = config.services.zuul-scheduler;
  zuul = pkgs.callPackage ./zuul.nix { inherit inputs; };
in {
  options.services.zuul-scheduler = {
    enable = lib.mkEnableOption "Enable zuul-scheduler";
    config = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Zuul system configuration
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.zuul-scheduler = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = let
        zuulConf = pkgs.writeText "zuul.conf" (lib.generators.toINI {} cfg.config);
        zuul-scheduler = pkgs.symlinkJoin rec {
          name = "zuul-scheduler";
          paths = with pkgs; [
            zuul
            bubblewrap
          ];
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
        };
      in "${zuul-scheduler}/bin/zuul-scheduler -f -c ${zuulConf}";
    };
  };
}
