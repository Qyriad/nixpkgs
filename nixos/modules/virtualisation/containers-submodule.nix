{
  ...
}@host:

{
  lib,
  config,
  options,
  name,
  ...
}@modArgs:
let
  inherit (lib)
    types
    mkOption
    mkDefault
    stringLength
    literalExpression
    showFiles
    mkMerge
    mkIf
  ;

  t = lib.types;
  renderExtraVeth = name: cfg: ''
    handleExtraVeth "${name}" \
      "${toString cfg.localAddress}" \
      "${toString cfg.hostAddress}" \
      "${toString cfg.localAddress6}" \
      "${toString cfg.hostAddress6}"
  '';

  kernelVersion = host.config.boot.kernelPackages.kernel.version;

  bindMountOpts = { name, ... }: {
    options = {
      mountPoint = mkOption {
        example = "/mnt/usb";
        type = types.str;
        description = "Mount point on the container file system.";
      };

      hostPath = mkOption {
        default = null;
        example = "/home/alice";
        type = types.nullOr types.str;
        description = "Location of the host path to be mounted.";
      };

      isReadOnly = mkOption {
        default = true;
        type = types.bool;
        description = "Determine whether the mounted path will be accessed in read-only mode.";
      };
    };

    config = {
      mountPoint = mkDefault name;
    };
  };

  allowedDeviceOpts = { ... }: {
    options = {
      node = mkOption {
        example = "/dev/net/tun";
        type = types.str;
        description = "Path to device node";
      };
      modifier = mkOption {
        example = "rw";
        type = types.str;
        description = ''
          Device node access modifier. Takes a combination
          `r` (read), `w` (write), and
          `m` (mknod). See the
          {manpage}`systemd.resource-control(5)` man page for more
          information.'';
      };
    };
  };


  networkOptions = {
    hostBridge = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "br0";
      description = ''
        Put the host-side of the veth-pair into the named bridge.
        Only one of hostAddress* or hostBridge can be given.
      '';
    };

    forwardPorts = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            protocol = mkOption {
              type = types.str;
              default = "tcp";
              description = "The protocol specifier for port forwarding between host and container";
            };
            hostPort = mkOption {
              type = types.port;
              description = "Source port of the external interface on host";
            };
            containerPort = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Target port of container";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          protocol = "tcp";
          hostPort = 8080;
          containerPort = 80;
        }
      ];
      description = ''
        List of forwarded ports from host to container. Each forwarded port
        is specified by protocol, hostPort and containerPort. By default,
        protocol is tcp and hostPort and containerPort are assumed to be
        the same if containerPort is not explicitly given.
      '';
    };

    hostAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.231.136.1";
      description = ''
        The IPv4 address assigned to the host interface.
        (Not used when hostBridge is set.)
      '';
    };

    hostAddress6 = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "fc00::1";
      description = ''
        The IPv6 address assigned to the host interface.
        (Not used when hostBridge is set.)
      '';
    };

    localAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.231.136.2";
      description = ''
        The IPv4 address assigned to the interface in the container.
        If a hostBridge is used, this should be given with netmask to access
        the whole network. Otherwise the default netmask is /32 and routing is
        set up from localAddress to hostAddress and back.
      '';
    };

    localAddress6 = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "fc00::2";
      description = ''
        The IPv6 address assigned to the interface in the container.
        If a hostBridge is used, this should be given with netmask to access
        the whole network. Otherwise the default netmask is /128 and routing is
        set up from localAddress6 to hostAddress6 and back.
      '';
    };

  };


  evalConfig = config.nixpkgs + "/nixos/lib/eval-config.nix";

  extraConfig = { options, ... }: {
    _file = "module at ${__curPos.file}:${toString __curPos.line}";
    config = {
      nixpkgs =
        if options.nixpkgs ? hostPlatform then
          { inherit (host.pkgs.stdenv) hostPlatform; }
        else
          { localSystem = host.pkgs.stdenv.hostPlatform; };
      boot.isContainer = true;
      networking.hostName = mkDefault name;
      networking.useDHCP = false;
      assertions = [
        {
          assertion =
            (builtins.compareVersions kernelVersion "5.8" <= 0)
            -> config.privateNetwork
            -> stringLength name <= 11;
          message = ''
            Container name `${name}` is too long: When `privateNetwork` is enabled, container names can
            not be longer than 11 characters, because the container's interface name is derived from it.
            You should either make the container name shorter or upgrade to a more recent kernel that
            supports interface altnames (i.e. at least Linux 5.8 - please see https://github.com/NixOS/nixpkgs/issues/38509
            for details).
          '';
        }
        {
          assertion = !lib.strings.hasInfix "_" name;
          message = ''
            Names containing underscores are not allowed in nixos-containers. Please rename the container '${name}'
          '';
        }
      ];
    };
  };

  mergeConfig = loc: defs: import evalConfig {
    modules = [ extraConfig ] ++ (map (x: x.value) defs);

    prefix = [ "containers" name ];

    inherit (config) specialArgs;

    # The system is inherited from the host above.
    # Set it to null, to remove the "legacy" entrypoint's non-hermetic default.
    system = null;
  };
in
{
  options = {
    config = mkOption {
      description = ''
        A specification of the desired configuration of this
        container, as a NixOS module.
      '';
      type = lib.mkOptionType {
        name = "Toplevel NixOS config";
        merge = loc: defs: (mergeConfig loc defs).config;
      };
    };

    path = mkOption {
      type = types.path;
      example = "/nix/var/nix/profiles/per-container/webserver";
      description = ''
        As an alternative to specifying
        {option}`config`, you can specify the path to
        the evaluated NixOS system configuration, typically a
        symlink to a system profile.
      '';
    };

    additionalCapabilities = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "CAP_NET_ADMIN"
        "CAP_MKNOD"
      ];
      description = ''
        Grant additional capabilities to the container.  See the
        {manpage}`capabilities(7)` and {manpage}`systemd-nspawn(1)` man pages for more
        information.
      '';
    };

    nixpkgs = mkOption {
      type = types.path;
      default = host.pkgs.path;
      defaultText = literalExpression "pkgs.path";
      description = ''
        A path to the nixpkgs that provide the modules, pkgs and lib for evaluating the container.

        To only change the `pkgs` argument used inside the container modules,
        set the `nixpkgs.*` options in the container {option}`config`.
        Setting `config.nixpkgs.pkgs = pkgs` speeds up the container evaluation
        by reusing the system pkgs, but the `nixpkgs.config` option in the
        container config is ignored in this case.
      '';
    };

    specialArgs = mkOption {
      type = types.attrsOf types.unspecified;
      default = { };
      description = ''
        A set of special arguments to be passed to NixOS modules.
        This will be merged into the `specialArgs` used to evaluate
        the NixOS configurations.
      '';
    };

    ephemeral = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Runs container in ephemeral mode with the empty root filesystem at boot.
        This way container will be bootstrapped from scratch on each boot
        and will be cleaned up on shutdown leaving no traces behind.
        Useful for completely stateless, reproducible containers.

        Note that this option might require to do some adjustments to the container configuration,
        e.g. you might want to set
        {var}`systemd.network.networks.$interface.dhcpV4Config.ClientIdentifier` to "mac"
        if you use {var}`macvlans` option.
        This way dhcp client identifier will be stable between the container restarts.

        Note that the container journal will not be linked to the host if this option is enabled.
      '';
    };

    enableTun = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Allows the container to create and setup tunnel interfaces
        by granting the `NET_ADMIN` capability and
        enabling access to `/dev/net/tun`.
      '';
    };

    privateNetwork = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to give the container its own private virtual
        Ethernet interface.  The interface is called
        `eth0`, and is hooked up to the interface
        `ve-«container-name»`
        on the host.  If this option is not set, then the
        container shares the network interfaces of the host,
        and can bind to any port on any interface.
      '';
    };

    networkNamespace = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Takes the path to a file representing a kernel network namespace that the container
        shall run in. The specified path should refer to a (possibly bind-mounted) network
        namespace file, as exposed by the kernel below /proc/<PID>/ns/net. This makes the
        container enter the given network namespace. One of the typical use cases is to give
        a network namespace under /run/netns created by {manpage}`ip-netns(8)`.
        Note that this option cannot be used together with other network-related options,
        such as --private-network or --network-interface=.
      '';
    };

    privateUsers = mkOption {
      type = types.either types.ints.u32 (
        types.enum [
          "no"
          "identity"
          "pick"
        ]
      );
      default = "no";
      description = ''
        Whether to give the container its own private UIDs/GIDs space (user namespacing).
        Disabled by default (`no`).

        If set to a number (usually above host's UID/GID range: 65536),
        user namespacing is enabled and the container UID/GIDs will start at that number.

        If set to `identity`, mostly equivalent to `0`, this will only provide
        process capability isolation (no UID/GID isolation, as they are the same as host).

        If set to `pick`, user namespacing is enabled and the UID/GID range is automatically chosen,
        so that no overlapping UID/GID ranges are assigned to multiple containers.
        This is the recommanded option as it enhances container security massively and operates fully automatically in most cases.

        See <https://www.freedesktop.org/software/systemd/man/latest/systemd-nspawn.html#--private-users=> for details.
      '';
    };

    interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "eth1"
        "eth2"
      ];
      description = ''
        The list of interfaces to be moved into the container.
      '';
    };

    macvlans = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "eth1"
        "eth2"
      ];
      description = ''
        The list of host interfaces from which macvlans will be
        created. For each interface specified, a macvlan interface
        will be created and moved to the container.
      '';
    };

    extraVeths = mkOption {
      type =
        with types;
        attrsOf (submodule {
          options = networkOptions;
          config = {

          };
        });
      default = { };
      description = ''
        Extra veth-pairs to be created for the container.
      '';
    };

    extraVethsRendered = mkOption {
      type = t.lines;
      internal = true;
      readOnly = true;

      default = config.extraVeths
      |> lib.mapAttrsToList renderExtraVeth
      |> lib.concatStringsSep "\n";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether the container is automatically started at boot-time.
      '';
    };

    restartIfChanged = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the container should be restarted during a NixOS
        configuration switch if its definition has changed.
      '';
    };

    timeoutStartSec = mkOption {
      type = types.str;
      default = "1min";
      description = ''
        Time for the container to start. In case of a timeout,
        the container processes get killed.
        See {manpage}`systemd.time(7)`
        for more information about the format.
      '';
    };

    bindMounts = mkOption {
      type = with types; attrsOf (submodule bindMountOpts);
      default = { };
      example = literalExpression ''
        { "/home" = { hostPath = "/home/alice";
                      isReadOnly = false; };
        }
      '';

      description = ''
        An extra list of directories that is bound to the container.
      '';
    };

    allowedDevices = mkOption {
      type = with types; listOf (submodule allowedDeviceOpts);
      default = [ ];
      example = [
        {
          node = "/dev/net/tun";
          modifier = "rwm";
        }
      ];
      description = ''
        A list of device nodes to which the containers has access to.
      '';
    };

    tmpfs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "/var" ];
      description = ''
        Mounts a set of tmpfs file systems into the container.
        Multiple paths can be specified.
        Valid items must conform to the --tmpfs argument
        of systemd-nspawn. See {manpage}`systemd-nspawn(1)` for details.
      '';
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--drop-capability=CAP_SYS_CHROOT" ];
      description = ''
        Extra flags passed to the systemd-nspawn command.
        See {manpage}`systemd-nspawn(1)` for details.
      '';
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "github:NixOS/nixpkgs/master";
      description = ''
        The Flake URI of the NixOS configuration to use for the container.
        Replaces the option {option}`containers.<name>.path`.
      '';
    };

    finalConfig = lib.mkOption {
      type = t.attrsOf t.anything;
      internal = true;
      readOnly = true;

      default = {
        inherit (config)
          extraVeths
          additionalCapabilities
          ephemeral
          timeoutStartSec
          allowedDevices
          hostAddress
          hostAddress6
          localAddress
          localAddress6
          tmpfs
        ;
      };
    };

    finalStartScript = mkOption {
      type = t.package;
      internal = true;
      readOnly = true;

      default = host.pkgs.callPackage ./start-script.nix {
        systemd = host.config.systemd.package;
        containerConfig = config.finalConfig // {
          inherit (config) finalInitScript;
        };
      };
    };

    finalInitScript = mkOption {
      type = t.package;
      internal = true;
      readOnly = true;

      default = host.pkgs.callPackage ./nixos-containers/container-init.nix {
        ##containerConfig = (builtins.trace modArgs.config modArgs.config)
        #|> lib.mapAttrs (_: value: value.value or value);
        containerConfig = {
          inherit (modArgs.config)
            extraVeths
            extraVethsRendered
            finalConfig
          ;
        };
      };
    };

    # Removed option. See `checkAssertion` below for the accompanying error message.
    pkgs = mkOption { visible = false; };
  }
  // networkOptions;

  config =
    let
      # Throw an error when removed option `pkgs` is used.
      # Because this is a submodule we cannot use `mkRemovedOptionModule` or option `assertions`.
      optionPath = "containers.${name}.pkgs";
      files = showFiles options.pkgs.files;
      checkAssertion =
        if options.pkgs.isDefined then
          throw ''
            The option definition `${optionPath}' in ${files} no longer has any effect; please remove it.

            Alternatively, you can use the following options:
            - containers.${name}.nixpkgs
              This sets the nixpkgs (and thereby the modules, pkgs and lib) that
              are used for evaluating the container.

            - containers.${name}.config.nixpkgs.pkgs
              This only sets the `pkgs` argument used inside the container modules.
          ''
        else if options.config.isDefined && (options.flake.value != null) then
          throw ''
            The options 'containers.${name}.path' and 'containers.${name}.flake' cannot both be set.
          ''
        else
          null;
    in
    {
      path = builtins.seq checkAssertion mkMerge [
        (mkIf options.config.isDefined config.config.system.build.toplevel)
        (mkIf (config.flake != null) "/nix/var/nix/profiles/per-container/${name}")
      ];
    };
}
