# Troubleshooting

## Install

### `composer create-project` dies partway with a curl error

```
curl error 18 while downloading ... HTTP/2 stream N was not closed cleanly
```

Transient, and it happened during this rig's own build. Retry with reduced
parallelism:

```bash
bin/php-run env COMPOSER_MAX_PARALLEL_HTTP=4 composer install --prefer-dist
```

### Install fails waiting for services

```bash
bin/dc ps                    # look for "healthy"
bin/dc logs db
bin/dc logs opensearch
```

OpenSearch is the usual culprit — it needs a raised `vm.max_map_count` on some
hosts:

```bash
sudo sysctl -w vm.max_map_count=262144
```

### Port already in use

Another stack has the port. Change `HTTP_PORT`, `DB_PORT`, or
`OPENSEARCH_PORT` in `.env`, then `bin/dc up -d`. If you change `HTTP_PORT`,
also update `BASE_URL` and reinstall, or fix the stored URL:

```bash
bin/mage setup:store-config:set --base-url="http://localhost:8480/"
bin/mage cache:flush
```

---

## Modules

### Magento doesn't see a linked module

Check the link resolves **inside** the container, which is the whole failure
mode the rig is designed around:

```bash
bin/php-run ls -la app/code/MageOS/
bin/php-run test -f app/code/MageOS/Blog/registration.php && echo OK
```

If that fails, `MODULES_PATH` in `.env` doesn't match the path the symlink was
written with. Re-link:

```bash
bin/link-module module-blog MageOS Blog
```

Then:

```bash
bin/mage module:status MageOS_Blog
bin/mage module:enable MageOS_Blog
bin/mage setup:upgrade
```

### A duplicate copy is being loaded

If the module is also present in `magento/vendor/`, that copy may win:

```bash
bin/php-run ls magento/vendor/<vendor>/ 2>/dev/null
bin/php-run composer remove <vendor>/<package>
```

### Code changes don't show up

Escalating order:

```bash
bin/mage cache:flush
bin/mage setup:upgrade                 # after db_schema/di changes
bin/mage setup:di:compile              # after constructor/DI changes
rm -rf magento/generated/* magento/var/cache/* magento/var/view_preprocessed/*
```

Static assets in developer mode:

```bash
rm -rf magento/pub/static/frontend/*
bin/mage cache:flush
```

---

## Integration tests

### First run takes forever

Expected — the framework installs a complete throwaway Magento into
`magento_integration_tests`. Later runs reuse it.

### "Unable to connect to the database" / access denied

Confirm the schemas exist and the user can reach them:

```bash
bin/dc exec -T db mariadb -uroot -proot -e "show databases;"
```

They are created by `docker/db/init/01-integration-db.sql`, which runs **only
on first boot of an empty data volume**. If the volume predates that file:

```bash
bin/dc down -v      # deletes the database
bin/install
```

### Tests pass individually but fail together

Usually missing isolation. Check the test class has:

```php
/**
 * @magentoDbIsolation enabled
 * @magentoAppIsolation enabled
 */
```

### Fixture store or product not found

Legacy fixtures are referenced by path, e.g.
`@magentoDataFixture Magento/Store/_files/store.php`. Resolve created ids at
runtime rather than hardcoding them — auto-increment values are not stable
across runs, and foreign keys will reject invented ids.

---

## Permissions

### Files owned by root after a container command

The wrappers pass `--user "$(id -u):$(id -g)"` precisely to avoid this, so it
means a raw `docker compose` call was used. Fix and prefer the wrappers:

```bash
sudo chown -R "$(id -u):$(id -g)" magento
```

---

## Starting over

Cheaper than debugging a confused install:

```bash
bin/dc down -v
rm -rf magento
bin/install
```
