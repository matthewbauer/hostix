{ lib, pkgs, config, ... }:

let
  cfg = config.hostix;
  inherit (config.networking) hostName;
  hosts = builtins.fromJSON (builtins.readFile cfg.hostsFile);

in {
  options.hostix.hostsFile = lib.mkOption {
    type = lib.types.path;
    description = ''
      JSON file to read hosts list from.
    '';
  };

  config = {

    nix = {
      binaryCaches = map (v: "https://${v.domain}${lib.optionalString (v ? cachePort) ":${toString v.cachePort}"}")
                         (lib.attrValues (lib.filterAttrs (_: v: v.cache or false) hosts));
      binaryCachePublicKeys = map (v: v.cachePublicKey)
        (lib.attrValues (lib.filterAttrs (_: v: v.cache or false) hosts));
      buildMachines = lib.mapAttrsToList (name: value: {
        hostName = name;
        sshUser = value.sshUser;
        sshKey = value.sshKey;
        system = value.system;
        maxJobs = value.maxJobs or 1;
        supportedFeatures = value.supportedFeatures or [];
      }) (lib.filterAttrs (host: v: v.builder or false && host != hostName) hosts);
      # maxJobs = hosts.${hostName}.maxJobs or 1;
    };

    programs.ssh.extraConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: value: ''
        Host ${name}
          Hostname ${value.domain}
          User ${value.sshUser}
          Port ${toString (value.ssh or 22)}
          ${lib.optionalString (value ? jump) "  ProxyJump ${value.jump}"}
       '') (lib.filterAttrs (_: v: v ? ssh) hosts));

    systemd.services.port-map = lib.mkIf (!(hosts.${hostName} ? jump) && hosts.${hostName} ? ssh) {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.miniupnpc}/bin/upnpc -r 22 ${toString hosts.${hostName}.ssh or 22} tcp";
      };
    };

    services.ddclient = lib.mkIf (!(hosts.${hostName} ? jump) && hosts.${hostName} ? ddclient) {
      enable = true;
      domains = [ "${hosts.${hostName}.domain}" ];
    } // hosts.${hostName}.ddclient;

  };


}
