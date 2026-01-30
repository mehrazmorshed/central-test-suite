#!/usr/bin/env bash

set -euo pipefail

########################################
# 0. Input validation
########################################

if [ $# -ne 1 ]; then
    echo "❌ Usage: $0 <path-to-plugin>"
    echo
    echo "Example:"
    echo "  $0 /Applications/MAMP/htdocs/ftl-lw/wp-content/plugins/location-weather"
    echo "  $0 ../wp-content/plugins/my-plugin"
    exit 1
fi

########################################
# 1. Resolve paths safely
########################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$1" = /* ]]; then
    PLUGIN_ROOT="$(cd "$1" && pwd)"
else
    PLUGIN_ROOT="$(cd "$SCRIPT_DIR/$1" && pwd)"
fi

if [ ! -d "$PLUGIN_ROOT" ]; then
    echo "❌ Error: Plugin directory not found:"
    echo "   $PLUGIN_ROOT"
    exit 1
fi

PLUGIN_NAME="$(basename "$PLUGIN_ROOT")"

REPORT_BASE="$SCRIPT_DIR/qa-reports"
REPORT_DIR="$REPORT_BASE/$PLUGIN_NAME"

mkdir -p "$REPORT_DIR"

########################################
# 2. Header
########################################

echo "🔍 Running WordPress Plugin QA"
echo "📁 Plugin: $PLUGIN_NAME"
echo "📂 Plugin root: $PLUGIN_ROOT"
echo "📋 Reports directory: $REPORT_DIR"
echo "----------------------------------------"

########################################
# 3. Direct access protection check
########################################

echo "➡️ Checking ABSPATH / WPINC guards..."

php <<PHP > "$REPORT_DIR/missing-abspath-wpinc.txt"
<?php

\$pluginRoot = realpath('$PLUGIN_ROOT');

\$rii = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator(\$pluginRoot, RecursiveDirectoryIterator::SKIP_DOTS),
    RecursiveIteratorIterator::LEAVES_ONLY
);

\$skipDirs = [
    DIRECTORY_SEPARATOR . 'vendor' . DIRECTORY_SEPARATOR,
    DIRECTORY_SEPARATOR . 'node_modules' . DIRECTORY_SEPARATOR,
    DIRECTORY_SEPARATOR . '.git' . DIRECTORY_SEPARATOR,
    DIRECTORY_SEPARATOR . '.github' . DIRECTORY_SEPARATOR,
    DIRECTORY_SEPARATOR . 'qa-reports' . DIRECTORY_SEPARATOR,
    DIRECTORY_SEPARATOR . 'dist' . DIRECTORY_SEPARATOR,
    DIRECTORY_SEPARATOR . 'tests' . DIRECTORY_SEPARATOR,
];

foreach (\$rii as \$file) {
    if (\$file->getExtension() !== 'php') {
        continue;
    }

    \$path = \$file->getPathname();

    foreach (\$skipDirs as \$dir) {
        if (strpos(\$path, \$dir) !== false) {
            continue 2;
        }
    }

    \$content = @file_get_contents(\$path);
    if (\$content === false) {
        continue;
    }

    if (
        strpos(\$content, "defined( 'ABSPATH' )") === false &&
        strpos(\$content, 'defined(\"ABSPATH\")') === false &&
        strpos(\$content, 'WPINC') === false
    ) {
        echo \$path . PHP_EOL;
    }
}
PHP

########################################
# 4. PHP Compatibility (PHP 7.4)
########################################

echo "➡️ Running PHPCompatibility (PHP 7.4)..."

phpcs "$PLUGIN_ROOT" \
  --standard=PHPCompatibility \
  --runtime-set testVersion 7.4 \
  --extensions=php \
  --ignore=*/vendor/*,*/node_modules/*,*/.git/*,*/qa-reports/*,*/dist/*,*/tests/* \
  --report=full \
  > "$REPORT_DIR/php-compatibility.txt" 2>&1 || true

########################################
# 5. WordPress Coding Standards
########################################

echo "➡️ Running WordPress Coding Standards..."

phpcs "$PLUGIN_ROOT" \
  --standard=WordPress \
  --extensions=php \
  --ignore=*/vendor/*,*/node_modules/*,*/build/*,*/.git/*,*/qa-reports/*,*/dist/*,*/tests/* \
  --exclude=WordPress.WP.I18n,WordPress.NamingConventions.PrefixAllGlobals,WordPress.Files.FileName,WordPress.Classes.ClassFileName \
  --report=full \
  > "$REPORT_DIR/wpcs.txt" 2>&1 || true

########################################
# 6. Summary
########################################

echo "----------------------------------------"
echo "✅ QA completed for: $PLUGIN_NAME"
echo
echo "📌 Reports generated:"
echo " - $REPORT_DIR/missing-abspath-wpinc.txt"
echo " - $REPORT_DIR/php-compatibility.txt"
echo " - $REPORT_DIR/wpcs.txt"
