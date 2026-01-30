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

########################################
# 7. Plugin activation / deactivation test
########################################

echo "➡️ Testing plugin activation & deactivation via WP-CLI..."

PLUGIN_SLUG="$PLUGIN_NAME"

# Detect WordPress root (3 levels up from plugin)
WP_ROOT="$(cd "$PLUGIN_ROOT/../../.." && pwd)"

# Ensure WP is accessible
if ! wp --path="$WP_ROOT" core is-installed --quiet; then
    echo "❌ WordPress not detected at $WP_ROOT"
    exit 1
fi

# Store current plugin state
if wp --path="$WP_ROOT" plugin is-active "$PLUGIN_SLUG"; then
    WAS_ACTIVE=true
else
    WAS_ACTIVE=false
fi

# Deactivate first (safe)
wp --path="$WP_ROOT" plugin deactivate "$PLUGIN_SLUG" --quiet || {
    echo "❌ Failed to deactivate plugin"
    exit 1
}

# Activate
wp --path="$WP_ROOT" plugin activate "$PLUGIN_SLUG" || {
    echo "❌ Plugin activation FAILED"
    exit 1
}

# Deactivate again
wp --path="$WP_ROOT" plugin deactivate "$PLUGIN_SLUG" || {
    echo "❌ Plugin deactivation FAILED"
    exit 1
}

# Restore original state
if [ "$WAS_ACTIVE" = true ]; then
    wp --path="$WP_ROOT" plugin activate "$PLUGIN_SLUG" --quiet
fi

echo "✅ Plugin activation/deactivation check passed"
########################################
# 8. PHP syntax lint (fatal errors)
########################################

echo "➡️ Running PHP syntax lint..."

php -d detect_unicode=0 -r '
$rii = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator("'"$PLUGIN_ROOT"'", RecursiveDirectoryIterator::SKIP_DOTS)
);

$errors = 0;

foreach ($rii as $file) {
    if ($file->getExtension() !== "php") {
        continue;
    }

    $path = $file->getPathname();

    if (preg_match("#/(vendor|node_modules|tests|dist|qa-reports)/#", $path)) {
        continue;
    }

    exec("php -l " . escapeshellarg($path), $out, $code);
    if ($code !== 0) {
        echo "Syntax error: $path\n";
        $errors++;
    }
}

exit($errors > 0 ? 1 : 0);
' > "$REPORT_DIR/php-lint.txt" 2>&1 || true
########################################
# 9. Uninstall safety check
########################################

echo "➡️ Checking uninstall safety..."

if [ -f "$PLUGIN_ROOT/uninstall.php" ]; then
    echo "uninstall.php found" > "$REPORT_DIR/uninstall.txt"
else
    echo "uninstall.php NOT found (ensure uninstall hook exists)" > "$REPORT_DIR/uninstall.txt"
fi

grep -R "register_uninstall_hook" "$PLUGIN_ROOT" >> "$REPORT_DIR/uninstall.txt" || true
########################################
# 10. Activation test with WP_DEBUG enabled
########################################

echo "➡️ Testing activation with WP_DEBUG enabled..."

wp --path="$WP_ROOT" config set WP_DEBUG true --raw --quiet
wp --path="$WP_ROOT" config set WP_DEBUG_LOG true --raw --quiet
wp --path="$WP_ROOT" config set WP_DEBUG_DISPLAY false --raw --quiet

wp --path="$WP_ROOT" plugin activate "$PLUGIN_SLUG" \
  > "$REPORT_DIR/wp-debug-activation.txt" 2>&1 || true

wp --path="$WP_ROOT" plugin deactivate "$PLUGIN_SLUG" --quiet || true

wp --path="$WP_ROOT" config set WP_DEBUG false --raw --quiet
wp --path="$WP_ROOT" config set WP_DEBUG_LOG false --raw --quiet
wp --path="$WP_ROOT" config set WP_DEBUG_DISPLAY false --raw --quiet
########################################
# 11. AJAX & REST handlers scan
########################################

echo "➡️ Scanning AJAX & REST handlers..."

grep -R "wp_ajax_" "$PLUGIN_ROOT" \
  | grep -v vendor \
  > "$REPORT_DIR/ajax-handlers.txt" || true

grep -R "register_rest_route" "$PLUGIN_ROOT" \
  | grep -v vendor \
  > "$REPORT_DIR/rest-routes.txt" || true
########################################
# 12. Nonce & permission checks
########################################

echo "➡️ Scanning nonce & permission checks..."

grep -R "check_admin_referer" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/nonces.txt" || true

grep -R "current_user_can" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/capability-checks.txt" || true
########################################
# 13. Database usage scan
########################################

echo "➡️ Scanning database usage..."

grep -R "\$wpdb->query" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/db-queries.txt" || true

grep -R "\$wpdb->prepare" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/db-prepared.txt" || true
########################################
# 14. Filesystem write scan
########################################

echo "➡️ Scanning filesystem writes..."

grep -R "file_put_contents" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/fs-file_put_contents.txt" || true

grep -R "fopen(" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/fs-fopen.txt" || true
########################################
# 15. Remote request scan
########################################

echo "➡️ Scanning remote HTTP calls..."

grep -R "wp_remote_" "$PLUGIN_ROOT" \
  > "$REPORT_DIR/remote-requests.txt" || true

########################################
# 16. i18n – issue detection only
########################################

# 1. Missing textdomain
grep -R --include="*.php" -E "\b(__|_e|esc_html__|esc_attr__)\s*\(\s*['\"][^'\"]+['\"]\s*\)" "$PLUGIN_ROOT" \
  | grep -vE "/(vendor|node_modules|tests|dist|build)/" \
  > "$REPORT_DIR/i18n-missing-textdomain.txt" || true

# 2. Textdomain loader
grep -R --include="*.php" "load_plugin_textdomain" "$PLUGIN_ROOT" \
  | grep -vE "/(vendor|node_modules|tests|dist|build)/" \
  > "$REPORT_DIR/i18n-loader.txt" || true


########################################
# 17. High-risk PHP function scan (PHP only)
########################################

echo "➡️ Scanning high-risk PHP functions..."

grep -R --include="*.php" -E "\b(eval|exec|shell_exec|passthru|system|popen|proc_open|base64_decode)\s*\(" "$PLUGIN_ROOT" \
  | grep -vE "/(vendor|node_modules|tests|dist|build|qa-reports)/" \
  > "$REPORT_DIR/high-risk-functions.txt" || true


