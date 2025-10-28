#! @runtimeShell@ -e

# Exit early if we're asked to shut down.
trap "exit 0" SIGRTMIN+3

function handleExtraVeth() {
  set -euo pipefail
  local name="$1"
  local locAddr="${2:-}"
  local hostAddr="${3:-}"
  local locAddr6="${4:-}"
  local hostAddr6="${5:-}"

  echo "Bringing $name up"
  ip link set dev "$name" up

  if [[ -n "${locAddr:-}" ]]; then
    echo "Setting ip for $name"
    ip addr add "$locAddr" dev "$name"
  fi

  if [[ -n "${locAddr6:-}" ]]; then
    echo "Setting ip6 for $name"
    ip -6 addr add "$locAddr6" dev "$name"
  fi

  if [[ -n "${hostAddr:-}" ]]; then
    echo "Setting route to host for $name"
    ip route add "$hostAddr" dev "$name"
  fi

  if [[ -n "${hostAddr6:-}" ]]; then
    echo "Setting route6 to host for $name"
    ip -6 route add "$HOST_ADDRESS6" dev "$name"
  fi
}

# Initialise the container side of the veth pair.
if [ -n "$HOST_ADDRESS" ]   || [ -n "$HOST_ADDRESS6" ]  ||
   [ -n "$LOCAL_ADDRESS" ]  || [ -n "$LOCAL_ADDRESS6" ] ||
   [ -n "$HOST_BRIDGE" ]; then
  ip link set host0 name eth0
  ip link set dev eth0 up

  if [ -n "$LOCAL_ADDRESS" ]; then
    ip addr add $LOCAL_ADDRESS dev eth0
  fi
  if [ -n "$LOCAL_ADDRESS6" ]; then
    ip -6 addr add $LOCAL_ADDRESS6 dev eth0
  fi
  if [ -n "$HOST_ADDRESS" ]; then
    ip route add $HOST_ADDRESS dev eth0
    ip route add default via $HOST_ADDRESS
  fi
  if [ -n "$HOST_ADDRESS6" ]; then
    ip -6 route add $HOST_ADDRESS6 dev eth0
    ip -6 route add default via $HOST_ADDRESS6
  fi
fi

@handleExtraVeths@

# Start the regular stage 2 script.
# We source instead of exec to not lose an early stop signal, which is
# also the only _reliable_ shutdown signal we have since early stop
# does not execute ExecStop* commands.
set +e
source "$1"

