{
  config,
  lib,
  pkgs,
  ...
}@host:

with lib;

let

  configurationPrefix = optionalString (versionAtLeast config.system.stateVersion "22.05") "nixos-";
  configurationDirectoryName = "${configurationPrefix}containers";
  configurationDirectory = "/etc/${configurationDirectoryName}";
  stateDirectory = "/var/lib/${configurationPrefix}containers";

  nixos-container = pkgs.nixos-container.override {
    inherit stateDirectory configurationDirectory;
  };

  startScript = cfg: pkgs.callPackage ./start-script.nix {
    systemd = config.systemd.package;
    containerConfig = cfg;
  };

  preStartScript = cfg: ''
    # Clean up existing machined registration and interfaces.
    machinectl terminate "$INSTANCE" 2> /dev/null || true

    if [ -n "$HOST_ADDRESS" ]  || [ -n "$LOCAL_ADDRESS" ] ||
       [ -n "$HOST_ADDRESS6" ] || [ -n "$LOCAL_ADDRESS6" ]; then
      ip link del dev "ve-$INSTANCE" 2> /dev/null || true
      ip link del dev "vb-$INSTANCE" 2> /dev/null || true
    fi

    ${concatStringsSep "\n" (
      mapAttrsToList (name: cfg: "ip link del dev ${name} 2> /dev/null || true ") cfg.extraVeths
    )}
  '';

  postStartScript = cfg: let
    ipcall = cfg: ipcmd: variable: attribute:
      if cfg.${attribute} == null then ''
        if [ -n "${variable}" ]; then
          ${ipcmd} add "${variable}" dev "$ifaceHost"
        fi
      ''
      else (
        ''${ipcmd} add ${cfg.${attribute}} dev "$ifaceHost"''
      );

    renderExtraVeth =
      name: cfg:
      if cfg.hostBridge != null then ''
        # Add ${name} to bridge ${cfg.hostBridge}
        ip link set dev "${name}" master "${cfg.hostBridge}" up
      ''
      else ''
        echo "Bring ${name} up"
        ip link set dev "${name}" up
        # Set IPs and routes for ${name}
        ${optionalString (cfg.hostAddress != null) ''
          ip addr add ${cfg.hostAddress} dev "${name}"
        ''}
        ${optionalString (cfg.hostAddress6 != null) ''
          ip -6 addr add ${cfg.hostAddress6} dev "${name}"
        ''}
        ${optionalString (cfg.localAddress != null) ''
          ip route add ${cfg.localAddress} dev "${name}"
        ''}
        ${optionalString (cfg.localAddress6 != null) ''
          ip -6 route add ${cfg.localAddress6} dev "${name}"
        ''}
      '';
    in
    ''
      if [ -n "$HOST_ADDRESS" ]  || [ -n "$LOCAL_ADDRESS" ] ||
         [ -n "$HOST_ADDRESS6" ] || [ -n "$LOCAL_ADDRESS6" ]; then
        if [ -z "$HOST_BRIDGE" ]; then
          ifaceHost=ve-$INSTANCE
          ip link set dev "$ifaceHost" up

          ${ipcall cfg "ip addr" "$HOST_ADDRESS" "hostAddress"}
          ${ipcall cfg "ip -6 addr" "$HOST_ADDRESS6" "hostAddress6"}
          ${ipcall cfg "ip route" "$LOCAL_ADDRESS" "localAddress"}
          ${ipcall cfg "ip -6 route" "$LOCAL_ADDRESS6" "localAddress6"}
        fi
      fi
      ${concatStringsSep "\n" (mapAttrsToList renderExtraVeth cfg.extraVeths)}
    ''
  ;

  serviceDirectives = cfg: {
    ExecReload = pkgs.writeScript "reload-container" ''
      #! ${pkgs.runtimeShell} -e
      ${nixos-container}/bin/nixos-container run "$INSTANCE" -- \
        bash --login -c "''${SYSTEM_PATH:-/nix/var/nix/profiles/system}/bin/switch-to-configuration test"
    '';

    SyslogIdentifier = "container %i";

    EnvironmentFile = "-${configurationDirectory}/%i.conf";

    Type = "notify";

    RuntimeDirectory = lib.optional cfg.ephemeral "${configurationDirectoryName}/%i";

    # Note that on reboot, systemd-nspawn returns 133, so this
    # unit will be restarted. On poweroff, it returns 0, so the
    # unit won't be restarted.
    RestartForceExitStatus = "133";
    SuccessExitStatus = "133";

    # Some containers take long to start
    # especially when you automatically start many at once
    TimeoutStartSec = cfg.timeoutStartSec;

    Restart = "on-failure";

    Slice = "machine.slice";
    Delegate = true;

    # We rely on systemd-nspawn turning a SIGTERM to itself into a shutdown
    # signal (SIGRTMIN+3) for the inner container.
    KillMode = "mixed";
    KillSignal = "TERM";

    DevicePolicy = "closed";
    DeviceAllow = map (d: "${d.node} ${d.modifier}") cfg.allowedDevices;
  };

  mkBindFlag =
    d:
    let
      flagPrefix = if d.isReadOnly then " --bind-ro=" else " --bind=";
      mountstr = if d.hostPath != null then "${d.hostPath}:${d.mountPoint}" else "${d.mountPoint}";
    in
    flagPrefix + mountstr;

  mkBindFlags = bs: concatMapStrings mkBindFlag (lib.attrValues bs);

  containerType = types.submodule (
    lib.modules.importApply ./containers-submodule.nix host
  );

  dummyConfig = (lib.evalModules {
    modules = containerType.getSubModules;
  }).config;

in

{
  options = {

    boot.isContainer = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether this NixOS machine is a lightweight container running
        in another NixOS system.
      '';
    };

    boot.enableContainers = mkOption {
      type = types.bool;
      default = config.containers != { };
      defaultText = lib.literalExpression "config.containers != { }";
      description = ''
        Whether to enable support for NixOS containers.
      '';
    };

    containers = mkOption {
      type = types.attrsOf (
        containerType
      );

      default = { };
      example = literalExpression ''
        { webserver =
            { path = "/nix/var/nix/profiles/webserver";
            };
          database =
            { config =
                { config, pkgs, ... }:
                { services.postgresql.enable = true;
                  services.postgresql.package = pkgs.postgresql_14;

                  system.stateVersion = "${lib.trivial.release}";
                };
            };
        }
      '';
      description = ''
        A set of NixOS system configurations to be run as lightweight
        containers.  Each container appears as a service
        `container-«name»`
        on the host system, allowing it to be started and stopped via
        {command}`systemctl`.
      '';
    };

  };

  config = mkMerge [
    {
      warnings =
        optional (!config.boot.enableContainers && config.containers != { })
          "containers.<name> is used, but boot.enableContainers is false. To use containers.<name>, set boot.enableContainers to true.";

      assertions =
        let
          mapper =
            name: cfg:
            optional (cfg.networkNamespace != null && (cfg.privateNetwork || cfg.interfaces != [ ]))
              "containers.${name}.networkNamespace is mutally exclusive to containers.${name}.privateNetwork and containers.${name}.interfaces.";
        in
        mkMerge (mapAttrsToList mapper config.containers);
    }

    (mkIf (config.boot.enableContainers) (
      let
        unit = {
          description = "Container '%i'";

          unitConfig.RequiresMountsFor = "${stateDirectory}/%i";

          path = [
            pkgs.iproute2
            config.nix.package
          ];

          environment = {
            root = "${stateDirectory}/%i";
            INSTANCE = "%i";
          };

          preStart = preStartScript dummyConfig;

          script = "source ${lib.getExe (startScript dummyConfig)}";

          postStart = postStartScript dummyConfig;

          restartIfChanged = false;

          serviceConfig = serviceDirectives dummyConfig;
        };
      in
      {
        warnings = (
          optional
            (config.virtualisation.containers.enable && versionOlder config.system.stateVersion "22.05")
            ''
              Enabling both boot.enableContainers & virtualisation.containers on system.stateVersion < 22.05 is unsupported.
            ''
        );

        systemd.targets.multi-user.wants = [ "machines.target" ];

        systemd.services = listToAttrs (
          filter (x: x.value != null) (
            # The generic container template used by imperative containers
            [
              {
                name = "container@";
                value = unit;
              }
            ]
            # declarative containers
            ++ (mapAttrsToList (
              name: cfg:
              nameValuePair "container@${name}" (
                let
                  containerConfig =
                    cfg
                    // (optionalAttrs cfg.enableTun {
                      allowedDevices = cfg.allowedDevices ++ [
                        {
                          node = "/dev/net/tun";
                          modifier = "rwm";
                        }
                      ];
                      additionalCapabilities = cfg.additionalCapabilities ++ [ "CAP_NET_ADMIN" ];
                    })
                    // (optionalAttrs
                      (
                        !cfg.enableTun
                        && cfg.privateNetwork
                        && (cfg.privateUsers == "pick" || (builtins.isInt cfg.privateUsers && cfg.privateUsers > 0))
                      )
                      {
                        allowedDevices = cfg.allowedDevices ++ [
                          {
                            node = "/dev/net/tun";
                            modifier = "rwm";
                          }
                        ];
                      }
                    );
                in
                recursiveUpdate unit {
                  preStart = preStartScript containerConfig;
                  #script = "source ${lib.getExe (startScript containerConfig)}";
                  script = "source ${lib.getExe containerConfig.finalStartScript}";
                  postStart = postStartScript containerConfig;
                  serviceConfig = (serviceDirectives containerConfig) // {
                  };
                  unitConfig.RequiresMountsFor =
                    lib.optional (!containerConfig.ephemeral) "${stateDirectory}/%i"
                    ++ builtins.map (d: if d.hostPath != null then d.hostPath else d.mountPoint) (
                      builtins.attrValues cfg.bindMounts
                    );
                  environment.root =
                    if containerConfig.ephemeral then "/run/nixos-containers/%i" else "${stateDirectory}/%i";
                }
                // (optionalAttrs containerConfig.autoStart {
                  wantedBy = [ "machines.target" ];
                  wants = [ "network.target" ] ++ (map (i: "sys-subsystem-net-devices-${i}.device") cfg.interfaces);
                  after = [ "network.target" ] ++ (map (i: "sys-subsystem-net-devices-${i}.device") cfg.interfaces);
                  restartTriggers = [
                    containerConfig.path
                    config.environment.etc."${configurationDirectoryName}/${name}.conf".source
                  ];
                  restartIfChanged = containerConfig.restartIfChanged;
                })
              )
            ) config.containers)
          )
        );

        # Generate a configuration file in /etc/nixos-containers for each
        # container so that container@.target can get the container
        # configuration.
        environment.etc =
          let
            mkPortStr =
              p:
              p.protocol
              + ":"
              + (toString p.hostPort)
              + ":"
              + (if p.containerPort == null then toString p.hostPort else toString p.containerPort);
          in
          mapAttrs' (
            name: cfg:
            nameValuePair "${configurationDirectoryName}/${name}.conf" {
              text = ''
                ${optionalString (cfg.flake == null) ''
                  SYSTEM_PATH=${cfg.path}
                ''}
                ${optionalString (cfg.flake != null) ''
                  FLAKE=${cfg.flake}
                ''}
                ${optionalString cfg.privateNetwork ''
                  PRIVATE_NETWORK=1
                  ${optionalString (cfg.hostBridge != null) ''
                    HOST_BRIDGE=${cfg.hostBridge}
                  ''}
                  ${optionalString (length cfg.forwardPorts > 0) ''
                    HOST_PORT=${concatStringsSep "," (map mkPortStr cfg.forwardPorts)}
                  ''}
                  ${optionalString (cfg.hostAddress != null) ''
                    HOST_ADDRESS=${cfg.hostAddress}
                  ''}
                  ${optionalString (cfg.hostAddress6 != null) ''
                    HOST_ADDRESS6=${cfg.hostAddress6}
                  ''}
                  ${optionalString (cfg.localAddress != null) ''
                    LOCAL_ADDRESS=${cfg.localAddress}
                  ''}
                  ${optionalString (cfg.localAddress6 != null) ''
                    LOCAL_ADDRESS6=${cfg.localAddress6}
                  ''}
                ''}
                ${optionalString (cfg.networkNamespace != null) ''
                  NETWORK_NAMESPACE_PATH=${cfg.networkNamespace}
                ''}
                PRIVATE_USERS=${toString cfg.privateUsers}
                INTERFACES="${toString cfg.interfaces}"
                MACVLANS="${toString cfg.macvlans}"
                ${optionalString cfg.autoStart ''
                  AUTO_START=1
                ''}
                EXTRA_NSPAWN_FLAGS="${
                  mkBindFlags cfg.bindMounts
                  + optionalString (cfg.extraFlags != [ ]) (" " + concatStringsSep " " cfg.extraFlags)
                }"
              '';
            }
          ) config.containers;

        # Generate /etc/hosts entries for the containers.
        networking.extraHosts = concatStrings (
          mapAttrsToList (
            name: cfg:
            optionalString (cfg.localAddress != null) ''
              ${head (splitString "/" cfg.localAddress)} ${name}.containers
            ''
          ) config.containers
        );

        networking.dhcpcd.denyInterfaces = [
          "ve-*"
          "vb-*"
        ];

        services.udev.extraRules = optionalString config.networking.networkmanager.enable ''
          # Don't manage interfaces created by nixos-container.
          ENV{INTERFACE}=="v[eb]-*", ENV{NM_UNMANAGED}="1"
        '';

        environment.systemPackages = [
          nixos-container
        ];

        boot.kernelModules = [
          "bridge"
          "macvlan"
          "tap"
          "tun"
        ];
      }
    ))
  ];

  meta.buildDocsInSandbox = false;
}
