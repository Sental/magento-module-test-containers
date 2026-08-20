-- The Magento integration test framework installs a throwaway Magento into this
-- schema and drops/recreates it on every run. It is created here so the test
-- user does not need CREATE DATABASE privileges.
CREATE DATABASE IF NOT EXISTS magento_integration_tests
    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

GRANT ALL PRIVILEGES ON magento_integration_tests.* TO 'magento'@'%';

-- The framework also uses a scratch schema when running with parallel workers.
CREATE DATABASE IF NOT EXISTS magento_integration_tests_2
    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

GRANT ALL PRIVILEGES ON magento_integration_tests_2.* TO 'magento'@'%';

FLUSH PRIVILEGES;
