# Maintenance

What accumulates in this rig, what cleans itself up, and which command to reach
for.

## The short answer

| Situation | Command | Cost |
|---|---|---|
| Finished with a module | `bin/unlink-module <Vendor> <Name>` | seconds |
| Disk creeping up | `bin/clean --cache` | seconds |
| Been running integration tests a lot | `bin/clean --tests` | seconds |
| Something is behaving inexplicably | `bin/reset --db-only` | ~10 min |
| Install has genuinely drifted | `bin/reset` | ~25 min |

Start with `bin/clean` on its own — it only reports, and tells you which of the
above you actually need.

## Module tables clean themselves up

The obvious worry with a shared rig is orphaned tables piling up as modules get
linked and unlinked. In practice **Magento handles this itself**, because of
declarative schema.

`db_schema.xml` is a declaration, not a migration. On `setup:upgrade` Magento
reconciles the database against the schema declared by all *enabled* modules,
and drops anything no longer declared. Disabling a module therefore removes its
tables on the next upgrade.

Verified here: `MageOS_Blog` creates 11 tables. After `module:disable` +
`setup:upgrade`, `information_schema` reports **0**. Re-enabling and upgrading
brings all 11 back.

The one trap is ordering. Magento can only drop tables for a module it still
knows about, and it learns that from `app/etc/config.php`. If you delete the
symlink *first*, the module vanishes from Magento's view with its tables still
in place and nothing left to attribute them to. `bin/unlink-module` does it in
the safe order for you.

Two consequences worth noting:

- A module with **no** `db_schema.xml` leaves nothing behind anyway.
- A module that writes rows to shared tables — `core_config_data`, `url_rewrite`,
  `search_query` — leaves those rows behind. They are small, but they are why
  `bin/reset` still has a place.

## What genuinely accumulates

**Integration-test schemas.** The framework installs a complete Magento
(~400 tables) into `magento_integration_tests` and never drops it. This is the
single biggest reclaim. `bin/clean --tests` drops and recreates the schemas
empty; the next test run reinstalls, so expect one slow run afterwards.

**Generated code and caches.** `magento/var` and `magento/generated` grow with
every compile and page render — routinely 10–15 MB, more after `di:compile`.
`bin/clean --cache` clears them; everything rebuilds on the next request. This
is also the correct first response to "my change isn't showing up".

**Logs and reports.** `var/log/system.log`, `var/log/exception.log`, and
`var/report/` grow without bound. Included in `--cache`.

**OpenSearch indices.** Magento writes versioned indices
(`magento_product_1_v5`, `_v6`, …) and query-log indices accumulate daily.
`bin/clean --search` deletes and reindexes.

**Composer cache.** The `modtest_composer-cache` volume reaches a few hundred
MB. Leave it — it is what makes `bin/reset` bearable, since the vendor download
comes from cache rather than the network. Only `bin/reset` (full) removes it.

## Reset vs clean

They answer different questions.

`bin/clean` is for known, bounded accumulation: caches, logs, test schemas,
search indices. Seconds, no reinstall, keeps your linked modules and data.

`bin/reset` is for *unknown* state — a half-applied schema change, a module
that left rows in shared tables, config you no longer remember setting, an
install you have poked at for a fortnight. Rather than diagnosing which of a
hundred possibilities is wrong, throw it away: everything is reproducible from
`.env` and `docker-compose.yml`.

Prefer `--db-only` when the vendor tree is fine and only the *data* is suspect.
It keeps `magento/vendor`, skipping the download, which is most of the time
difference.

`bin/reset` names everything it will destroy and requires you to type `reset`.
Linked modules are listed before you confirm, and their repos are never touched
— only symlinks are removed.

## Routine

There isn't much of one. This rig is disposable by design, which is the whole
reason not to be precious about it:

- `bin/clean` before wondering whether something is wrong
- `bin/clean --cache` when a change won't appear
- `bin/clean --tests` after a heavy integration-testing session
- `bin/reset` whenever diagnosing would take longer than rebuilding
