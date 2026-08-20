# Module Testing Rig

A disposable, containerised **Mage-OS 3.4.0** install for exercising Magento
modules that live *outside* this directory — in their own git repos, edited in
place, loaded live by a real store.

Everything runs in Docker. Your host needs Docker and nothing else: no PHP, no
Composer, no MySQL.

```bash
cp .env.example .env       # then set MODULES_PATH
bin/install                # ~20-30 min with sample data

bin/link-module module-blog MageOS Blog
bin/mage module:enable MageOS_Blog
bin/mage setup:upgrade
```

| | |
|---|---|
| Storefront | <http://localhost:8380/> |
| Admin | <http://localhost:8380/admin> — `admin` / `Admin123!` |
| Ships with | Mage-OS 3.4.0 (Magento 2.4.9), PHP 8.4, MariaDB 11.4, OpenSearch 2.19, sample data |

## The one idea worth understanding

Modules are **not copied in**. Each is bind-mounted from wherever it already
lives straight into `app/code`, so you edit code in its own repo and the store
picks it up immediately:

```yaml
services:
  php:
    volumes:
      - /srv/modules/module-blog:/var/www/html/app/code/MageOS/Blog
```

`bin/link-module` generates that into `docker-compose.override.yml` and
recreates the containers. Point `MODULES_PATH` anywhere; nothing else changes.

### Why a mount and not a symlink

A symlink is the obvious approach and it **silently breaks Magento**.

`registration.php` calls `ComponentRegistrar::register(..., __DIR__)`, and PHP
resolves `__DIR__` through symlinks. A symlinked module therefore registers its
*real* path — outside the Magento root — and Magento's filesystem
`PathValidator` rejects every template it owns:

```
ValidatorException: Path "/srv/modules/module-blog/view/frontend/templates/post/view.phtml"
cannot be used with directory "/var/www/html/"
```

The cruel part is how late it fails. Class autoloading, `db_schema.xml`, DI and
layout XML parsing all work perfectly with a symlink — tables get created, the
module reports as enabled, unit tests pass. It only falls over when a `.phtml`
renders, as an HTTP 500 that names a path that plainly exists.

A bind mount gives the module a genuine path inside the Magento root, so
`__DIR__` lands inside `BP` and the validator is satisfied.

## Documentation

| Guide | |
|---|---|
| [Getting started](docs/getting-started.md) | First install, what to expect, verifying it worked |
| [Commands](docs/commands.md) | Every `bin/` script, with examples |
| [Use cases](docs/use-cases.md) | Real workflows: test a module, run integration tests, check FPC, reproduce a bug |
| [Architecture](docs/architecture.md) | Services, ports, the module mount mechanism, what was deliberately left out |
| [Maintenance](docs/maintenance.md) | What accumulates, what cleans itself, reset vs clean |
| [Troubleshooting](docs/troubleshooting.md) | Things that go wrong and how to fix them |

`CLAUDE.md` is the orientation file for AI coding agents working in this repo.

## Housekeeping

```bash
bin/clean            # report what has accumulated (read-only)
bin/clean --cache    # caches, generated code, logs — seconds
bin/clean --tests    # drop the integration-test schemas
bin/reset --db-only  # wipe data, keep vendor, reinstall (~10 min)
bin/reset            # destroy and rebuild everything (~25 min)
```

Module tables need no cleanup command: Magento's declarative schema drops them
on `setup:upgrade` once a module is disabled, which is what `bin/unlink-module`
does for you. See [Maintenance](docs/maintenance.md).

`magento/` is gitignored — large, disposable, and rebuilt by one command.
