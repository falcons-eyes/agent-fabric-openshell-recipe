# Shared settings. Override any of these in the environment.
FABRIC="${FABRIC:-fabric}"                       # or fabric-staging
FABRIC_NETWORK="${FABRIC_NETWORK:-Default}"
PG_PORT="${PG_PORT:-55460}"
PGURL="${PGURL:-postgres://postgres:demo@127.0.0.1:${PG_PORT}/fintech}"
GATEWAY_PORT="${GATEWAY_PORT:-17777}"
# Where the gateway listens. On macOS (Docker Desktop) host.openshell.internal reaches
# the host's loopback, so 127.0.0.1 works. On Linux (DGX Spark) the sandbox reaches the
# host through the Docker bridge: listen on the bridge address, e.g. 172.17.0.1.
GATEWAY_LISTEN="${GATEWAY_LISTEN:-127.0.0.1:${GATEWAY_PORT}}"
MODEL_URL="${MODEL_URL:-http://host.openshell.internal:11434/v1}"
MODEL="${MODEL:-nemotron-3-nano:30b}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
