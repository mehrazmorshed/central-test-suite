# Central Test Suite

The test suite is used to check plugin coding standards or not.

## Prerequistes

1. PHPCS, PHPCBF, and wpcs should be installed globally.

## Usage

1.  Download this package to any folder and `cd central-test-suite`.
2.  run `chmod +x wp-qa-check.sh` command in terminal  // for other .sh files follow the same way.
3.  Then run the following command to test any plugin folder, like `./wp-qa-check.sh /Applications/MAMP/htdocs/ftl-lw/wp-content/plugins/location-weather`.
4.  After completion of the command, you will see qa-reports>location-weather folder in the central-test-suite folder.
5.  Check the report and fix it as soon as possible, and run it again.
