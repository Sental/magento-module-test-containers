# Getting started

## Requirements

Docker with the Compose plugin, and roughly **8 GB of free disk**. Nothing else —
no PHP, Composer, MySQL, or OpenSearch on the host.

Check Docker is usable:

```bash
docker compose version
```

## 1. Configure

```bash
cp .env.example .env
```

Open `.env` and set the one machine-specific value:

```bash
MODULES_PATH=/srv/modules
```

That is the directory holding the module repos you want to test. Everything
else has a working default. If you skip this step, `bin/install` creates `.env`
for you and tells you to check it.

Ports default to **8380** (web), **33406** (database), **9280** (OpenSearch) —
deliberately non-standard so the rig can run beside other local projects.

## 2. Install

```bash
bin/install
```

Expect **20–30 minutes**. The script:

1. starts MariaDB and OpenSearch, waiting for both to report healthy
2. runs `setup:install` against them
3. deploys sample data (~2000 products) and re-runs `setup:upgrade`
4. switches to developer mode, reindexes, flushes caches
5. starts nginx

Skip the slow part if you don't need catalog content:

```bash
bin/install --no-sample-data
```

Re-running is safe — it refuses to touch an existing install unless you pass
`--force`, which drops the database first.

## 3. Verify

```bash
bin/dc ps                                       # all four services up
curl -o /dev/null -w "%{http_code}\n" http://localhost:8380/    # 200
bin/mage --version                              # Mage-OS CLI 3.4.0
```

Then open <http://localhost:8380/> for the storefront and
<http://localhost:8380/admin> for the admin (`admin` / `Admin123!`).

## 4. Add a module

```bash
bin/link-module module-blog MageOS Blog
bin/mage module:enable MageOS_Blog
bin/mage setup:upgrade
bin/mage setup:di:compile
```

Arguments are `<directory under MODULES_PATH> <Vendor> <Name>`. The module is
symlinked, not copied — edit it in its own repo and the store sees the changes.

Remove it again with:

```bash
bin/unlink-module MageOS Blog
```

That deletes only the symlink. Your module repo is never touched.

## What you now have

A real Mage-OS 3.4.0 store, in developer mode, with a full sample catalogue,
that loads your module from its own git repo. Use it to click through
storefront changes, run integration tests, check cache behaviour, and reproduce
bugs against a realistic dataset.

Next: [Use cases](use-cases.md) for the workflows this was built for.
