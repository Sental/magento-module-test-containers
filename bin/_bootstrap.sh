#!/usr/bin/env bash
# Sourced by the other bin/ scripts. Moves to the rig root, creates .env from
# .env.example on a fresh clone, and loads it.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -f .env ]; then
    if [ ! -f .env.example ]; then
        echo "Neither .env nor .env.example found — is this the rig root?" >&2
        exit 1
    fi
    cp .env.example .env
    echo "Created .env from .env.example."
    echo "Check MODULES_PATH points at your modules directory before installing:"
    echo "  $(grep '^MODULES_PATH=' .env)"
    echo
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

if [ ! -d "${MODULES_PATH}" ]; then
    echo "MODULES_PATH does not exist: ${MODULES_PATH}" >&2
    echo "Edit .env and point it at your modules directory." >&2
    exit 1
fi

# Run containers as the invoking user so files written into the bind mount stay
# editable on the host.
DC_USER="$(id -u):$(id -g)"
export DC_USER

dc_run() { docker compose run --rm --user "$DC_USER" "$@"; }
