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

# Registry of linked modules: one "<dir> <Vendor> <Name>" line each.
LINKED_REGISTRY=.linked-modules

# Regenerate docker-compose.override.yml from the registry.
#
# Modules are bind-mounted straight into app/code rather than symlinked.
# registration.php calls ComponentRegistrar::register(..., __DIR__), and PHP
# resolves __DIR__ through symlinks — so a symlinked module registers its REAL
# path, outside BP. Magento's Filesystem PathValidator then refuses every
# template it owns:
#
#   ValidatorException: Path "/srv/modules/module-blog/view/.../view.phtml"
#   cannot be used with directory "/var/www/html/"
#
# Class autoloading, db_schema and DI all work regardless, so the breakage only
# shows when a .phtml renders. A bind mount gives the module a genuine path
# inside the Magento root, and __DIR__ then lands inside BP.
render_override() {
    local out=docker-compose.override.yml

    if [ ! -s "$LINKED_REGISTRY" ]; then
        rm -f "$out"
        return 0
    fi

    {
        echo "# GENERATED FILE — do not edit by hand."
        echo "# Managed by bin/link-module and bin/unlink-module."
        echo "#"
        echo "# Modules are bind-mounted into app/code, not symlinked: registration.php"
        echo "# uses __DIR__, which resolves symlinks, so a symlinked module registers a"
        echo "# path outside BP and Magento's PathValidator rejects its templates."
        echo "services:"
        local svc dir vendor name
        for svc in php web; do
            echo "  ${svc}:"
            echo "    volumes:"
            while read -r dir vendor name; do
                [ -z "${dir:-}" ] && continue
                echo "      - ${MODULES_PATH}/${dir}:/var/www/html/app/code/${vendor}/${name}"
            done < "$LINKED_REGISTRY"
        done
    } > "$out"
}
