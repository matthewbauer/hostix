{ lib, pkgs, config, ... }:

{
  options.hostix.hostsFile = lib.mkOption {
    type = lib.types.file;
    description = ''
      JSON file to read hosts list from.
    '';
  };

  config = let
    hosts = builtins.fromJSON (builtins.readFile config.hostsFile);
    inherit (config.networking) hostName;
  in {

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
          User ${value.user}
          Port ${toString (value.ssh or 22)}
          ${lib.optionalString (value ? jump) "  ProxyJump ${value.jump}"}
      '') hosts);

  } // lib.optionalAttrs (!(hosts.${hostName} ? jump) && hosts.${hostName} ? ssh) {
    systemd.services.port-map = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.miniupnpc}/bin/upnpc -r 22 ${toString hosts.${hostName}.ssh} tcp";
      };
    };

  } // lib.optionalAttrs (!(hosts.${hostName} ? jump) && hosts.${hostName} ? ddclient) {
    services.ddclient = {
      enable = true;
      domains = [ "${hosts.${hostName}.domain}" ];
    } // hosts.${hostName}.ddclient;
  };


}
