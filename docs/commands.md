# Command reference

Every script lives in `bin/` and is run from the rig root. They all source
`bin/_bootstrap.sh`, which moves to the rig root, creates `.env` from
`.env.example` if missing, loads it, and validates `MODULES_PATH`.

---

## `bin/install`

Builds the whole rig from nothing.

```bash
bin/install                    # with sample data (~20-30 min)
bin/install --no-sample-data   # faster; empty catalogue
bin/install --force            # DROPS the database and reinstalls
```

Refuses to run over an existing install unless `--force` is given. Locale,
currency, and timezone come from `STORE_LANGUAGE` / `STORE_CURRENCY` /
`STORE_TIMEZONE` in `.env` and can only be changed by reinstalling.

---

## `bin/install-hyva`

Adds Hyvä to an existing install and activates the default theme. Needed to test
a Hyvä compatibility module — without it, `setup:di:compile` fails on any
`di.xml` naming a `Hyva\…` class.

```bash
bin/install-hyva                      # install + activate Hyva/default
bin/install-hyva --no-activate        # install, leave the storefront on Luma
bin/install-hyva --theme=Magento/luma # switch the active theme back
```

Hyvä is commercial and on no public repository, so this reads `HYVA_REPO_URL`,
`HYVA_AUTH_USER` and `HYVA_AUTH_TOKEN` from `.env` — your own licence
credentials. It refuses to run without them rather than guessing.

Only the default scope is set. A store view with its own theme override keeps
it; change those under **Content > Design > Configuration**.

---

## `bin/uninstall-hyva`

Removes Hyvä and puts the storefront back on Luma.

```bash
bin/uninstall-hyva               # back to Magento/luma
bin/uninstall-hyva --keep-auth   # leave the stored composer credentials
```

**Order matters, as with `bin/unlink-module`.** The theme is switched back
*first* — including any store-scope overrides naming a Hyvä theme — because
removing the packages while a store still points at `Hyva/default` makes every
storefront request 500 on a theme whose files are gone.

Rows for the removed themes stay in the `theme` table. They are inert; Magento
re-registers themes from the filesystem.

---

## `bin/hyva-build`

Regenerates `app/etc/hyva-themes.json` and rebuilds the theme's Tailwind CSS.

```bash
bin/hyva-build                                  # default theme
bin/hyva-build --theme-dir=app/design/frontend/Acme/theme
bin/hyva-build --skip-config                    # CSS only
```

A compatibility module's **templates work on a cache flush; its styling does
not** — the CSS only exists once the module is listed in `hyva-themes.json` and
the theme has been rebuilt. This is the usual reason a module looks
half-applied.

The php image has no node, so the build runs in a throwaway `node:22-alpine`
container over the same `magento/` tree.

---

## `bin/reset`

Destroys the rig and rebuilds it from `.env` + `docker-compose.yml`. The blunt
instrument: everything here is reproducible from committed files, so a drifted
install is usually cheaper to rebuild than to diagnose.

```bash
bin/reset                    # containers, volumes, magento/ — everything
bin/reset --db-only          # keep magento/vendor; wipe data and reinstall
bin/reset --no-sample-data   # faster rebuild
bin/reset --yes              # skip the confirmation prompt
```

Prints exactly what it will destroy and requires you to type `reset` to
proceed. Lists any linked modules first — their own repos are never touched —
and prints the re-link commands at the end.

`--db-only` skips the Composer download by keeping the vendor tree, which is
the difference between roughly 10 minutes and 25.

---

## `bin/clean`

Reclaims space without a rebuild. **Running it bare only reports** — every
destructive action needs an explicit flag.

```bash
bin/clean            # report: disk, schemas, indices, volumes
bin/clean --cache    # caches, generated code, logs, reports, static assets
bin/clean --tests    # drop and recreate the integration-test schemas
bin/clean --search   # delete stale OpenSearch indices, then reindex
bin/clean --all      # all three
```

`--cache` is safe and routine: generated code and static assets rebuild on the
next request. It typically recovers 10–15 MB and is the right first move when
something behaves strangely. It also stop/starts `php` to reset opcache (a
`restart` signals the existing process and would not), restarts `web` so nginx
re-resolves the new php IP, and waits for the stack to answer before returning.

`--tests` matters more than it looks — the integration framework installs a
complete Magento (~400 tables) into `magento_integration_tests` and never drops
it. The next test run reinstalls, so expect one slow run afterwards.

> **You do not need this to remove a module's tables.** See below.

---

## `bin/link-module <dir> <Vendor> <Name>`

Bind-mounts a module from `$MODULES_PATH` into `app/code`, records it in
`.linked-modules`, regenerates `docker-compose.override.yml`, and recreates the
`php` and `web` containers.

```bash
bin/link-module module-blog MageOS Blog
# /srv/modules/module-blog -> /var/www/html/app/code/MageOS/Blog
```

It is a mount, not a symlink — a symlinked module registers a path outside the
Magento root and Magento then refuses to render its templates. See
[Architecture](architecture.md). Editing stays live in both directions.

Warns if the source has no `registration.php`, verifies the mount is visible
inside the container, and prints the enable/upgrade commands to run next.

## `bin/unlink-module <Vendor> <Name>`

Disables the module, drops its tables, and removes the mount — in that order,
which matters.

```bash
bin/unlink-module MageOS Blog
bin/unlink-module MageOS Blog --keep-tables   # leave the data alone
```

Only the mount is removed — the module's own repo is never touched. A leftover
empty mount point under `app/code` is cleaned up afterwards.

### Why the order matters

Magento's declarative schema drops a module's tables during `setup:upgrade`,
but only while the module is still listed in `app/etc/config.php`. So the
sequence is:

1. `module:disable` — module stays in `config.php`, marked `0`
2. `setup:upgrade` — declarative schema sees its tables are no longer declared and **drops them**
3. remove the mount

Unmount first and the tables are stranded: Magento no longer knows
they exist, and nothing will clean them up. This is handled for you, but it is
worth knowing if you ever unlink something by hand.

Verified on this rig: 11 `mageos_blog_*` tables, dropped to 0 by
`module:disable` + `setup:upgrade`, and recreated on re-enable.

---

## `bin/mage <args…>`

`bin/magento` inside the container.

```bash
bin/mage cache:flush
bin/mage setup:upgrade
bin/mage setup:di:compile
bin/mage module:status MageOS_Blog
bin/mage config:set mageos_blog/general/enabled 1
bin/mage indexer:reindex
bin/mage cache:disable full_page
```

---

## `bin/test-integration <path> [phpunit args…]`

Runs integration tests. Paths are relative to the Magento root **inside the
container** (`/var/www/html`), so a linked module is reached through
`app/code/`:

```bash
bin/test-integration app/code/MageOS/Blog/Test/Integration
bin/test-integration app/code/MageOS/Blog/Test/Integration/Model/PostsByProductTest.php
bin/test-integration app/code/MageOS/Blog/Test/Integration --filter test_excludes_drafts
```

Absolute container paths (`/var/www/html/app/code/...`) work too. Relative ones
are converted before being handed to PHPUnit, because PHPUnit `chdir()`s to the
directory holding the `-c` config file — without the conversion, a path relative
to the Magento root gets resolved against `dev/tests/integration/` and reported
as `Test file ... not found`.

On first use the script also installs `docker/magento/install-config-mysql.php`
into `dev/tests/integration/etc/`, replacing the framework's `.dist` template
(which points at `localhost` with Adobe's sample credentials). It is re-copied
whenever the committed version differs, so editing the template is enough.

> **First run is slow.** The framework installs a second, throwaway Magento
> into the `magento_integration_tests` schema. It owns and recreates that
> schema — never repoint it at a database you care about.

---

## `bin/php-run <command…>`

Any command in the PHP container, as your host user.

```bash
bin/php-run composer require --dev foo/bar
bin/php-run composer show mage-os/module-catalog
bin/php-run php -v
bin/php-run php -i | grep opcache
bin/php-run vendor/bin/phpunit --version
```

---

## `bin/dc <args…>`

Raw `docker compose`, always resolved from the rig root so it works from any
directory.

```bash
bin/dc ps
bin/dc logs -f web
bin/dc logs --tail 100 php
bin/dc restart php    # NB: signals the process; does NOT clear opcache
bin/dc stop php && bin/dc start php && bin/dc restart web   # this does
bin/dc up -d
bin/dc down          # stop, keep data
bin/dc down -v       # stop and DELETE database + search index
bin/dc exec db mariadb -uroot -proot magento
```

---

## Common one-liners

Database shell:

```bash
bin/dc exec db mariadb -uroot -proot magento
```

Query directly:

```bash
bin/dc exec -T db mariadb -uroot -proot magento -e "select count(*) from catalog_product_entity;"
```

Watch a Magento log:

```bash
tail -f magento/var/log/system.log
tail -f magento/var/log/exception.log
```

Full reset:

```bash
bin/reset            # or bin/reset --db-only to keep the vendor tree
```
