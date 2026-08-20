# Use cases

The workflows this rig exists for. Each assumes the module is already linked:

```bash
bin/link-module module-blog MageOS Blog
bin/mage module:enable MageOS_Blog
bin/mage setup:upgrade
```

---

## See a storefront change in a real store

The reason the rig exists. Edit the module in its own repo, reload the page.

```bash
vim /srv/modules/module-blog/view/frontend/templates/post/card.phtml
bin/mage cache:flush
open http://localhost:8380/blog
```

The module is bind-mounted into `app/code`, so edits are live with no sync step.

In developer mode, `.phtml` and layout XML changes need only a cache flush.
Changes to **DI, `db_schema.xml`, or `di.xml`** need more:

```bash
bin/mage setup:upgrade
bin/mage setup:di:compile
```

If a change genuinely refuses to appear, clear generated code:

```bash
rm -rf magento/generated/* magento/var/cache/* magento/var/view_preprocessed/*
bin/mage cache:flush
```

---

## Run a module's integration tests

Unit tests belong in the module's own repo (`composer test:unit` — no database
needed). Integration tests need a real Magento, which is what this rig is.

```bash
bin/test-integration app/code/MageOS/Blog/Test/Integration
```

Narrow it while iterating:

```bash
bin/test-integration app/code/MageOS/Blog/Test/Integration/Model/PostsByProductTest.php
bin/test-integration app/code/MageOS/Blog/Test/Integration --filter test_honours_the_limit
```

The first run installs a throwaway Magento into `magento_integration_tests` and
takes several minutes. Later runs reuse it.

---

## Verify full-page-cache invalidation

Cache bugs are invisible in unit tests and on a developer-mode page load. To
test them honestly you need FPC actually on:

```bash
bin/mage cache:enable full_page
bin/mage cache:flush

curl -s http://localhost:8380/blog/some-post > /dev/null   # populate
curl -s http://localhost:8380/blog/some-post > /dev/null   # now a cache hit
```

Change the entity in admin, then reload **without flushing**. If your block
declares correct `getIdentities()`, the change appears; if it doesn't, you'll
see the stale page — which is the bug.

Turn it back off while developing:

```bash
bin/mage cache:disable full_page
```

---

## Reproduce a bug against a realistic catalogue

Sample data gives ~2000 products and 40 categories, which surfaces problems an
empty install hides: N+1 queries, slow collection loads, pagination edge cases,
layered-navigation interactions.

```bash
bin/dc exec -T db mariadb -uroot -proot magento \
  -e "select entity_id, sku from catalog_product_entity limit 5;"
```

Use a real product id when testing product-page behaviour rather than
hand-inserting a fixture row.

---

## Test multi-store behaviour

Store-scope bugs are among the most common in Magento modules and need a second
store view to catch:

```bash
bin/mage config:set --scope=stores --scope-code=default some/path value
```

Create additional store views in the admin under
**Stores → All Stores**, then check your module honours the scope on both.

---

## Test config defaults on a clean install

For anything gated behind a config flag, the interesting case is the merchant
who never touched the setting:

```bash
bin/mage config:set mageos_blog/general/enabled 0
bin/mage cache:flush
curl -s http://localhost:8380/ | grep -c mageos-blog     # expect 0
```

---

## Work on several modules at once

Link as many as you like; they share one install.

```bash
bin/link-module module-blog MageOS Blog
bin/link-module module-seo  MageOS Seo
bin/mage module:enable MageOS_Blog MageOS_Seo
bin/mage setup:upgrade
```

---

## Hand the rig back clean

When finished with a module, remove its link but leave the rig standing for the
next one:

```bash
bin/unlink-module MageOS Blog
```

You do not need to clean up its tables — `bin/unlink-module` disables the
module and runs `setup:upgrade`, at which point Magento's declarative schema
drops them for you. See [Maintenance](maintenance.md).

If the install itself has drifted into a confusing state, rebuild rather than
debugging it — it is disposable by design:

```bash
bin/reset --db-only    # keep vendor, wipe data (~10 min)
bin/reset              # everything (~25 min)
```
