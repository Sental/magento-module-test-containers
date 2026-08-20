# CLAUDE.md

Orientation for AI coding agents working in this repository.

## What this is

A disposable, containerised **Mage-OS 3.4.0** (Magento 2.4.9) install used to
test Magento modules that live **outside** this directory, in their own git
repos. It is a test rig, not an application. Nothing here is deployed anywhere.

Human documentation lives in `docs/`. Read `docs/architecture.md` before
changing `docker-compose.yml` or anything in `docker/`.

## Rules

**Never commit `magento/`.** It is ~4 GB, machine-specific, gitignored, and
rebuildable with `bin/install`. If you find yourself staging it, stop.

**Never edit files under `magento/` expecting them to persist.** That tree is
disposable and gets wiped by `bin/install --force` or a rebuild. Real work
belongs in the module's own repo under `$MODULES_PATH`, or in this rig's
`bin/`, `docker/`, and `docs/`.

**Never run PHP, Composer, or MySQL on the host.** Everything goes through the
containers via `bin/`. The host's PHP version is irrelevant and using it will
produce results that do not match the rig.

**Never point the integration-test database at anything real.** The Magento
test framework drops and recreates `magento_integration_tests` on every run.

## Commands

Always from the rig root. Never `cd` into `magento/` to run things.

```bash
bin/install [--no-sample-data] [--force]   # build the rig
bin/link-module <dir> <Vendor> <Name>      # symlink a module in
bin/unlink-module <Vendor> <Name>          # disable, drop tables, remove symlink
bin/mage <bin/magento args>                # e.g. bin/mage cache:flush
bin/php-run <cmd>                          # arbitrary command in the php container
bin/test-integration <path> [phpunit args] # integration tests
bin/dc <docker compose args>               # raw compose from the rig root
bin/clean [--cache|--tests|--search|--all] # bare = report only
bin/reset [--db-only] [--no-sample-data]   # destroy and rebuild
```

`bin/test-integration` paths are relative to the Magento root **inside the
container** (`/var/www/html`), so a linked module is reached via `app/code/`:

```bash
bin/test-integration app/code/MageOS/Blog/Test/Integration
bin/test-integration app/code/MageOS/Blog/Test/Integration --filter test_name
```

## The symlink mechanism — do not break this

Modules are symlinked, not copied:

```
magento/app/code/MageOS/Blog -> /srv/modules/module-blog
```

That absolute path only resolves inside the container because
`docker-compose.yml` bind-mounts `${MODULES_PATH}` **at the identical path**:

```yaml
- ${MODULES_PATH}:${MODULES_PATH}
```

If you remove or rename that mount, every linked module silently disappears
from Magento. Both `php` and `web` need it — nginx serves module static assets
directly.

## Verifying a change actually took effect

Magento caches aggressively; "it didn't work" usually means "it wasn't
rebuilt". Escalate in this order, and do not claim a change works until a
storefront request proves it:

```bash
bin/mage cache:flush                       # templates, layout XML
bin/mage setup:upgrade                     # db_schema.xml, module version
bin/mage setup:di:compile                  # di.xml, constructor changes
rm -rf magento/generated/* magento/var/cache/*
```

Check a real response rather than reasoning about it:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8380/
curl -s http://localhost:8380/ | grep -c some-marker
```

## Full-page cache

FPC is the thing most likely to make a module look correct when it isn't. To
test invalidation you must actually enable it — a developer-mode page load
proves nothing about cache tags:

```bash
bin/mage cache:enable full_page
bin/mage cache:flush
# load twice, edit the entity in admin, reload WITHOUT flushing
```

If the stale version persists, the block is missing `IdentityInterface` /
`getIdentities()`.

## Facts

| | |
|---|---|
| Storefront | <http://localhost:8380/> |
| Admin | <http://localhost:8380/admin> — `admin` / `Admin123!` |
| Ports | web 8380, db 33406, opensearch 9280 |
| Compose project | `modtest` (containers are `modtest-db-1`, `modtest-php-1`, …) |
| Sample data | ~2040 products, 40 categories |
| Databases | `magento`, `magento_integration_tests`, `magento_integration_tests_2` |

## Cleaning up

Do **not** write ad-hoc `DROP TABLE` statements to remove a module's tables.
Magento's declarative schema does it: on `setup:upgrade` it reconciles the
database against the schema declared by enabled modules and drops what is no
longer declared.

Order is what matters — Magento can only drop tables for a module still listed
in `app/etc/config.php`:

1. `module:disable`
2. `setup:upgrade` ← tables dropped here
3. remove the symlink

Delete the symlink first and the tables are stranded with nothing to attribute
them to. `bin/unlink-module` already does this correctly; use it.

For anything else, `bin/clean` (bare, read-only) reports what has accumulated,
and `bin/reset` rebuilds from scratch when the state is not worth diagnosing.

## Gotchas that have already bitten

- **`tasklist.exe: not found` is never the real error.** The test framework
  measures memory with `ps` and, in a bare `catch`, treats *any* failure as
  "must be Windows" — then throws again, uncaught, replacing the actual error.
  It fires during shutdown, so it can bury a **passing** run: scroll to the top
  of the output before concluding anything. `procps` is installed to keep the
  Linux path working; Magento has not supported Windows since 2.2.7.
- `setup:install` validates AMQP whenever `amqp-*` params are present. This rig
  runs no RabbitMQ, so the test install config must omit them.
- PHPUnit `chdir()`s to the `-c` config file's directory, so test paths must be
  absolute. `bin/test-integration` converts them; do not bypass it.
- `composer create-project` can fail at ~99% with `curl error 18 ... HTTP/2
  stream not closed cleanly`. Retry with `COMPOSER_MAX_PARALLEL_HTTP=4`.
- `opcache` reports as `Zend OPcache` in `php -m` — grepping for `opcache`
  wrongly suggests it is missing.
- `web` cannot start before the install exists, because its nginx config
  `include`s Magento's `nginx.conf.sample` from the install tree.
- Legacy `@magentoDataFixture` ids are not stable. Resolve created store and
  product ids at runtime; foreign keys reject invented ones.

## When an error looks wrong, it probably is

Every masking failure in this rig's history hid a legible error behind an
illegible one. Before acting on the loudest message: find the **first** error in
the output, state whether it is the cause or merely a symptom, and say what
would falsify that reading. Do not fix the last thing you saw.
