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

If that fails, `MODULES_PATH` in `.env` doesn't match the path the mount was
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

### HTTP 500: `Path ... cannot be used with directory "/var/www/html/"`

The module is reachable through a **symlink** rather than a bind mount.
`registration.php` uses `__DIR__`, PHP resolves that through symlinks, so the
module registers a path outside the Magento root and `PathValidator` refuses
its templates. Everything else — schema, DI, autoloading — works, which is why
this only appears when a page renders.

`dev/template/allow_symlink` does **not** help; it feeds a clause of the
template validator that already passes. Re-link properly:

```bash
bin/link-module module-blog MageOS Blog
```

See [Architecture](architecture.md) for the full explanation.

### Code changes don't show up

Escalating order:

```bash
bin/mage cache:flush
bin/mage setup:upgrade                 # after db_schema/di changes
bin/mage setup:di:compile              # after constructor/DI changes
bin/clean --cache                      # + resets opcache (stop/start php)
```

**Opcache is the one people miss.** It lives in the FPM process's shared
memory, so deleting files on disk does nothing to it, and `docker compose
restart php` only signals the existing process. Only a new process drops the
cached bytecode:

```bash
bin/dc stop php && bin/dc start php && bin/dc restart web
```

The `web` restart is not optional: nginx caches the `php` upstream IP at
startup, and a restarted php container gets a new address — without it every
request 502s. `bin/clean --cache` does all of this and waits for the stack.

This bites hardest when a module's contents change under a running container.
The image sets `realpath_cache_ttl = 10` and `opcache.revalidate_freq = 0` to
reduce it, but a full process restart is the only guarantee.

Static assets in developer mode:

```bash
rm -rf magento/pub/static/frontend/*
bin/mage cache:flush
```

---

## Integration tests

### `tasklist.exe: not found` — read this before believing any other error

A Windows executable in a Linux container looks alarming and is deeply
misleading. It means something else failed, and this error is standing on top
of it.

`Magento\TestFramework\Helper\Memory::getRealMemoryUsage()` measures the real
resident set size by shelling out to `ps` (it avoids `memory_get_usage()`
because of [PHP bug 62467](https://bugs.php.net/bug.php?id=62467), which misses
memory allocated outside the Zend allocator). The method does **no** OS
detection whatsoever:

```php
try {
    $result = $this->_getUnixProcessMemoryUsage($pid);   // ps --pid N --format rss
} catch (\Magento\Framework\Exception\LocalizedException $e) {
    $result = $this->_getWinProcessMemoryUsage($pid);    // tasklist.exe
}
```

Any failure of the Unix command — missing `ps`, permissions, a restricted
`/proc` — is treated as evidence of running on Windows. It then throws a second,
uncaught exception, which replaces whatever was actually wrong. Magento has not
supported Windows since 2.2.7 (hardcoded `/` path separators), so this branch
can never succeed on any supported platform.

The rig installs `procps` so the Linux path works and the branch is unreachable.
If you see it anyway, `ps` is missing from the image — rebuild:

```bash
bin/dc build php
bin/php-run ps --pid 1 --format rss --no-headers    # should print a number
```

**It fires during shutdown**, after the suite has finished, so it can bury a
*passing* run as readily as a failing one — destroying the PHPUnit summary line
and the exit code. Always scroll to the top of the output.

### `Could not connect to the Amqp Server` / `Parameter validation failed`

`setup:install` validates the AMQP connection whenever `amqp-*` parameters are
present, and this rig runs no RabbitMQ. The framework's stock
`install-config-mysql.php.dist` sets them; the rig's replacement deliberately
omits them. If you have copied the `.dist` by hand, remove the `amqp-*` keys —
or add a rabbitmq service to `docker-compose.yml`.

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
bin/reset --db-only    # keep the vendor tree, wipe data (~10 min)
bin/reset              # everything (~25 min)
```
