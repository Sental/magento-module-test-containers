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

## The module mount mechanism

This is the part worth understanding, because the obvious approach to it is
wrong in a way that takes hours to diagnose.

Modules are never copied in. `bin/link-module` records the module in
`.linked-modules` and regenerates `docker-compose.override.yml`, which
bind-mounts it directly into `app/code`:

```yaml
services:
  php:
    volumes:
      - /srv/modules/module-blog:/var/www/html/app/code/MageOS/Blog
  web:
    volumes:
      - /srv/modules/module-blog:/var/www/html/app/code/MageOS/Blog
```

Both `php` and `web` need it — nginx serves module static assets directly.

### Why not a symlink

A symlink from `app/code/Vendor/Name` to the module repo is the natural first
design. It was this rig's original design, and it is broken.

`registration.php` calls `ComponentRegistrar::register(..., __DIR__)`, and PHP
resolves `__DIR__` through symlinks. The module therefore registers its **real**
path, outside the Magento root:

```text
registered at: /srv/modules/module-blog
BP:            /var/www/html
inside BP?     NO
```

`Magento\Framework\View\Element\Template\File\Validator::isValid()` then calls
`$this->getRootDirectory()->getRelativePath($filename)`, and the filesystem
`PathValidator` throws:

```text
ValidatorException: Path "/srv/modules/module-blog/view/frontend/templates/post/view.phtml"
cannot be used with directory "/var/www/html/"
```

What makes this expensive is how much still works. Autoloading, `db_schema.xml`,
`di.xml` and layout XML parsing are all path-agnostic — tables are created,
`module:status` says enabled, `setup:upgrade` succeeds, unit tests pass. It only
fails when a `.phtml` renders, as an HTTP 500 naming a file that plainly exists.

**`dev/template/allow_symlink` does not fix it.** That setting is the Magento 1
`allow_symlinks` descendant and it is the obvious thing to reach for. Look at
where it is actually used:

```php
($this->isPathInDirectories($filename, $this->_compiledDir)
    || $this->isPathInDirectories($filename, $this->moduleDirs)
    || $this->isPathInDirectories($filename, $this->_themesDir)
    || $this->_isAllowSymlinks)
&& $this->getRootDirectory()->isFile($this->getRootDirectory()->getRelativePath($filename));
```

It only ORs into the first clause — which already passes, because `moduleDirs`
contains the module's registered path. The exception comes from
`getRelativePath()` in the second clause, which runs unconditionally. Tested on
this rig: `allow_symlink=1` plus a symlink still returns HTTP 500 with the
identical exception.

Bind-mounting gives the module a genuine path inside the Magento root, so
`__DIR__` lands inside `BP` and the validator is satisfied.

Consequences worth knowing:

- **Adding or removing a module recreates `php` and `web`.** Volumes are fixed
  at container creation; `docker compose restart` will not pick up a new mount.
  The scripts use `up -d`, which recreates on config change.
- **`docker-compose.override.yml` is generated.** Do not hand-edit it. Both it
  and `.linked-modules` are gitignored.
- **`MODULES_PATH` must be absolute.** `_bootstrap.sh` fails early otherwise.
- **Moving a module repo breaks its mount.** Re-run `bin/link-module`.
- **Composer-installed copies win.** If the module is also in `magento/vendor/`,
  remove it or Magento may load that one instead.

## Caching when files change underneath

Module contents change under a running container, so the PHP image is tuned not
to trust cached paths or bytecode for long:

- `opcache.validate_timestamps = 1` with `revalidate_freq = 0` — every request
  stats the file and acts immediately.
- `realpath_cache_ttl = 10` seconds, not the production default. A long TTL is
  the usual cause of "I changed the file and nothing happened", and it gets far
  worse when mounts come and go.

Opcache still lives in the FPM **process's** shared memory, so deleting files on
disk does not clear it. Only a new process does — and `docker compose restart`
signals the existing one rather than replacing it. `bin/clean --cache` does a
stop/start instead.

One trap that follows: nginx resolves the `php` upstream once at startup and
caches the IP. A restarted php container gets a **new** address, and every
request then 502s against the old one. Anything that restarts `php` must also
restart `web`; `bin/clean` does, and waits for the stack to answer before
returning.

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

## Integration test configuration

`docker/magento/install-config-mysql.php` is the committed source of truth for
how the test framework installs its throwaway Magento. `bin/test-integration`
copies it into `magento/dev/tests/integration/etc/` whenever it differs, since
that destination lives under the gitignored `magento/` tree.

It differs from the framework's `.dist` template in two ways that matter:

- **Hosts are container service names** (`db`, `opensearch`), not `localhost`.
  The tests execute inside the `php` container.
- **No `amqp-*` keys.** `setup:install` validates the AMQP connection when they
  are present, and this rig runs no RabbitMQ, so their presence fails the
  install outright. Add them back only alongside a real rabbitmq service.

The PHP image also installs `procps`. The test framework measures memory with
`ps`, and on failure falls back to Windows' `tasklist.exe` — a branch that
cannot succeed on any platform Magento still supports, and which masks the real
error when it fires. See [Troubleshooting](troubleshooting.md).

## What is committed

Everything except `magento/` and `.env`. The install is large, machine-specific
and rebuildable in one command; `.env` holds machine-specific paths. Clone,
`cp .env.example .env`, set `MODULES_PATH`, `bin/install`.
