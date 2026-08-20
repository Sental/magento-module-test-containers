<?php
/**
 * Integration-test install config for this rig.
 *
 * Copied into magento/dev/tests/integration/etc/ by bin/test-integration.
 * Hosts are container service names, not localhost — the tests run inside the
 * php container, where `db` and `opensearch` are the reachable names.
 *
 * WARNING: the test framework OWNS db-name below. It drops and recreates that
 * schema on every run. Never point it at a database you care about.
 */

return [
    'db-host' => 'db',
    'db-user' => 'magento',
    'db-password' => 'magento',
    'db-name' => 'magento_integration_tests',
    'db-prefix' => '',
    'backend-frontname' => 'backend',
    'search-engine' => 'opensearch',
    'opensearch-host' => 'opensearch',
    'opensearch-port' => 9200,
    'admin-user' => \Magento\TestFramework\Bootstrap::ADMIN_NAME,
    'admin-password' => \Magento\TestFramework\Bootstrap::ADMIN_PASSWORD,
    'admin-email' => \Magento\TestFramework\Bootstrap::ADMIN_EMAIL,
    'admin-firstname' => \Magento\TestFramework\Bootstrap::ADMIN_FIRSTNAME,
    'admin-lastname' => \Magento\TestFramework\Bootstrap::ADMIN_LASTNAME,

    // The stock .dist template sets amqp-host/port/user/password. Keep them out:
    // setup:install VALIDATES the AMQP connection when they are present, and
    // this rig runs no RabbitMQ, so their presence fails the install with
    // "Could not connect to the Amqp Server / Parameter validation failed".
    // Add them back only alongside an actual rabbitmq service.
    'consumers-wait-for-messages' => '0',
];
