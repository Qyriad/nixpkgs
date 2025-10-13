# Declare root explicitly to avoid shellcheck warnings, it comes from the env
declare root

mkdir -p "$root/etc" "$root/var/lib"
chmod 0755 "$root/etc" "$root/var/lib"
mkdir -p "$root/var/lib/private" "$root/root" /run/nixos-containers
chmod 0700 "$root/var/lib/private" "$root/root" /run/nixos-containers
if ! [ -e "$root/etc/os-release" ] && ! [ -h "$root/etc/os-release" ]; then
  touch "$root/etc/os-release"
fi

if ! [ -e "$root/etc/machine-id" ]; then
  touch "$root/etc/machine-id"
fi

mkdir -p \
  "/nix/var/nix/profiles/per-container/$INSTANCE" \
  "/nix/var/nix/gcroots/per-container/$INSTANCE"
chmod 0755 \
  "/nix/var/nix/profiles/per-container/$INSTANCE" \
  "/nix/var/nix/gcroots/per-container/$INSTANCE"

cp --remove-destination /etc/resolv.conf "$root/etc/resolv.conf"

if [ -n "$FLAKE" ] && [ ! -e "/nix/var/nix/profiles/per-container/$INSTANCE/system" ]; then
  # we create the etc/nixos-container config file, then if we utilize the update function, we can then build all the necessary system files for the container
  #${lib.getExe nixos-container} update "$INSTANCE"
  "@nixos_container@" update "$INSTANCE"
fi

declare -a extraFlags

if [ "$PRIVATE_NETWORK" = 1 ]; then
  extraFlags+=("--private-network")
fi

NIX_BIND_OPT=""
if [ -n "$PRIVATE_USERS" ]; then
  extraFlags+=("--private-users=$PRIVATE_USERS")
  if [[ "$PRIVATE_USERS" = "pick" || ("$PRIVATE_USERS" =~ ^[[:digit:]]+$ && "$PRIVATE_USERS" -gt 0) ]]; then
    # when user namespacing is enabled, we use `idmap` mount option so that
    # bind mounts under /nix get proper owner (and not nobody/nogroup).
    NIX_BIND_OPT=":idmap"
  fi
fi

if [ -n "$HOST_ADDRESS" ]  || [ -n "$LOCAL_ADDRESS" ] ||
   [ -n "$HOST_ADDRESS6" ] || [ -n "$LOCAL_ADDRESS6" ]; then
  extraFlags+=("--network-veth")
fi

if [ -n "$HOST_PORT" ]; then
  OIFS=$IFS
  IFS=","
  for i in $HOST_PORT
  do
      extraFlags+=("--port=$i")
  done
  IFS=$OIFS
fi

if [ -n "$HOST_BRIDGE" ]; then
  extraFlags+=("--network-bridge=$HOST_BRIDGE")
fi

if [ -n "$NETWORK_NAMESPACE_PATH" ]; then
  extraFlags+=("--network-namespace-path=$NETWORK_NAMESPACE_PATH")
fi

extraFlags+=(@extra_veths@)

if [[ "@host_platform_system@" == "x86_64-linux" ]]; then
  if [ "$(< "${SYSTEM_PATH:-/nix/var/nix/profiles/per-container/$INSTANCE/system}/system")" = i686-linux ]; then
    extraFlags+=("--personality=x86")
  fi
fi

for iface in $INTERFACES; do
  extraFlags+=("--network-interface=$iface")
done

for iface in $MACVLANS; do
  extraFlags+=("--network-macvlan=$iface")
done

# If the host is 64-bit and the container is 32-bit, add a
# --personality flag.
if [[ "@host_platform_system@" == "x86_64-linux" ]]; then
  if [ "$(< "${SYSTEM_PATH:-/nix/var/nix/profiles/per-container/$INSTANCE/system}/system")" = "i686-linux" ]; then
    extraFlags+=("--personality=x86")
  fi
fi

export SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1

# Run systemd-nspawn without startup notification (we'll
# wait for the container systemd to signal readiness)
# Kill signal handling means systemd-nspawn will pass a system-halt signal
# to the container systemd when it receives SIGTERM for container shutdown;
# containerInit and stage2 have to handle this as well.
# TODO: fix shellcheck issue properly
# shellcheck disable=SC2086
exec @systemd_nspawn@ \
  --keep-unit \
  -M "$INSTANCE" -D "$root" "${extraFlags[@]}" \
  --notify-ready=yes \
  --kill-signal=SIGRTMIN+3 \
  --bind-ro=/nix/store:/nix/store$NIX_BIND_OPT \
  --bind-ro=/nix/var/nix/db:/nix/var/nix/db$NIX_BIND_OPT \
  --bind-ro=/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket$NIX_BIND_OPT \
  --bind="/nix/var/nix/profiles/per-container/$INSTANCE:/nix/var/nix/profiles$NIX_BIND_OPT" \
  --bind="/nix/var/nix/gcroots/per-container/$INSTANCE:/nix/var/nix/gcroots$NIX_BIND_OPT" \
  @link_journal_arg@ \
  --setenv PRIVATE_NETWORK="$PRIVATE_NETWORK" \
  --setenv PRIVATE_USERS="$PRIVATE_USERS" \
  --setenv HOST_BRIDGE="$HOST_BRIDGE" \
  --setenv HOST_ADDRESS="$HOST_ADDRESS" \
  --setenv LOCAL_ADDRESS="$LOCAL_ADDRESS" \
  --setenv HOST_ADDRESS6="$HOST_ADDRESS6" \
  --setenv LOCAL_ADDRESS6="$LOCAL_ADDRESS6" \
  --setenv HOST_PORT="$HOST_PORT" \
  --setenv PATH="$PATH" \
  @ephemeral_arg@ \
  @capability_arg@ \
  @tmpfs_arg@ \
  $EXTRA_NSPAWN_FLAGS \
  "@container_init@" \
  "${SYSTEM_PATH:-/nix/var/nix/profiles/system}/init"
