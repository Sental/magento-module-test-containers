# Architecture

## Layout

```
/srv/testing/
├── docker-compose.yml       # four services
├── .env                     # local config (gitignored)
├── .env.example             # committed template
├── bin/                     # wrapper scripts
│   ├── _bootstrap.sh        # sourced by all others
│   ├── install
│   ├── link-module / unlink-module
│   ├── mage / php-run / dc
│   └── test-integration
├── docker/
│   ├── php/Dockerfile       # PHP 8.4-FPM + extensions + Composer 2
│   ├── php/php.ini
│   ├── nginx/default.conf
│   └── db/init/*.sql        # creates the integration-test schemas
├── docs/
└── magento/                 # the install itself — gitignored, disposable
```

## Services

| Service | Image | Host port | Why |
|---|---|---|---|
| `db` | `mariadb:11.4` | 33406 | Main + integration-test schemas |
| `opensearch` | `opensearchproject/opensearch:2.19.1` | 9280 | Magento 2.4+ cannot install without a search engine |
| `php` | built from `docker/php` | — | PHP 8.4-FPM, Composer 2, all Mage-OS 3.4 extensions |
| `web` | `nginx:1.27-alpine` | 8380 | Fronts PHP-FPM |

Ports are non-default on purpose, so the rig coexists with other local stacks.
Change them in `.env`.

### Deliberately absent

No Varnish, Redis/Valkey, RabbitMQ, or cron container. This is a module test
rig, not a production mirror — each omission is one less thing to debug when a
module misbehaves. Magento's built-in file cache and cron-via-CLI cover the
cases that matter here. Add services to `docker-compose.yml` if a module under
test genuinely needs them.

## The symlink mechanism

This is the part worth understanding, because it is what makes the rig useful
and it is not obvious.

Modules are never copied into the install. `bin/link-module` writes an
**absolute** symlink:

```
magento/app/code/MageOS/Blog -> /srv/modules/module-blog
```

A symlink is just a stored string. `/srv/modules/module-blog` means
nothing inside a container that has never heard of that path, so the link would
dangle and Magento would not find the module.

The fix is to mount the modules directory at **the identical path** inside the
container:

```yaml
volumes:
  - ./magento:/var/www/html
  - ${MODULES_PATH}:${MODULES_PATH}     # /srv/modules -> /srv/modules
```

Now the same absolute path is valid on both sides, the link resolves in both
places, and you get to edit the module in its own git repo while a real store
loads it live.

Both `php` and `web` mount it, because nginx serves static assets straight from
the module directory.

Consequences worth knowing:

- **`MODULES_PATH` must be an absolute path**, and the same one used when
  linking. `_bootstrap.sh` fails early if the directory does not exist.
- **Moving a module repo breaks its link.** Re-run `bin/link-module`.
- **Composer-installed copies win.** If the same module is also in
  `magento/vendor/`, remove it or Magento may load that one instead.

## PHP image

`php:8.4-fpm-bookworm` plus every extension Mage-OS 3.4 requires — `bcmath`,
`gd`, `intl`, `mbstring`, `pdo_mysql`, `soap`, `sockets`, `sodium`, `xsl`,
`zip`, `opcache` — and Composer 2 copied from the official image.

Containers run as the invoking host user (`--user "$(id -u):$(id -g)"`, applied
by `_bootstrap.sh`) so files written into the bind mount stay editable outside
the container. This is why the wrappers exist rather than raw `docker compose
exec`.

`docker/php/php.ini` sets developer-friendly values: 4 GB memory limit, 30
minute max execution, `display_errors=On`, and opcache with
`validate_timestamps=1` so edited files take effect immediately.

## nginx

`docker/nginx/default.conf` sets `$MAGE_ROOT` and `$MAGE_MODE`, then includes
Magento's own `nginx.conf.sample` from the install rather than reimplementing
its routing. That file only exists after the project is created, which is why
`web` starts at the end of `bin/install`.

## Databases

`docker/db/init/01-integration-db.sql` runs on first database boot and creates
`magento_integration_tests` and `magento_integration_tests_2`, granting the
`magento` user rights to both. Creating them up front means the test user does
not need `CREATE DATABASE`.

> The Magento integration framework **owns** those schemas and drops/recreates
> them on every run. Never point them at anything you care about.

## What is committed

Everything except `magento/` and `.env`. The install is large, machine-specific
and rebuildable in one command; `.env` holds machine-specific paths. Clone,
`cp .env.example .env`, set `MODULES_PATH`, `bin/install`.
