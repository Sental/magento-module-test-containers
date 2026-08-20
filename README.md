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

Modules are **not copied in**. They are symlinked from wherever they already
live, so you edit code in its own repo and the store picks it up immediately.

```
magento/app/code/MageOS/Blog -> /srv/modules/module-blog
```

That absolute symlink would normally break inside a container, because
`/srv/modules` doesn't exist there. The compose file mounts it at the
*same path on both sides*, so the link resolves either way:

```yaml
volumes:
  - ./magento:/var/www/html
  - ${MODULES_PATH}:${MODULES_PATH}
```

Point `MODULES_PATH` anywhere; nothing else needs to change.

## Documentation

| Guide | |
|---|---|
| [Getting started](docs/getting-started.md) | First install, what to expect, verifying it worked |
| [Commands](docs/commands.md) | Every `bin/` script, with examples |
| [Use cases](docs/use-cases.md) | Real workflows: test a module, run integration tests, check FPC, reproduce a bug |
| [Architecture](docs/architecture.md) | Services, ports, the symlink mechanism, what was deliberately left out |
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
