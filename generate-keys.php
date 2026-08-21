<?php
// OLMEICK WC Bridge — API Key Generator
// Accessible at /generate-keys.php (no auth required)
header('Content-Type: application/json');
$_SERVER['PHP_SELF'] = '/wp-admin/admin-ajax.php';
$_SERVER['HTTPS'] = 'on';
require_once('/var/www/html/wp-load.php');
global $wpdb;

// Find admin user
$admin_id = (int) $wpdb->get_var("SELECT ID FROM {$wpdb->users} ORDER BY ID ASC LIMIT 1");
if (!$admin_id) { echo json_encode(['error' => 'No users in DB']); exit; }

// Load WooCommerce functions
$wc_api_file = WP_CONTENT_DIR . '/plugins/woocommerce/includes/class-wc-rest-api.php';
if (file_exists($wc_api_file)) { require_once($wc_api_file); }
$wc_auth_file = WP_CONTENT_DIR . '/plugins/woocommerce/includes/wc-rest-functions.php';
if (file_exists($wc_auth_file)) { require_once($wc_auth_file); }

// Delete old keys
$wpdb->delete($wpdb->prefix . 'woocommerce_api_keys', ['user_id' => $admin_id]);

// Try official WC function first
if (function_exists('wc_generate_api_key')) {
    $key_id = wc_generate_api_key(['user_id' => $admin_id, 'description' => 'OLMEICK Bridge Key']);
    if (!is_wp_error($key_id)) {
        $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM {$wpdb->prefix}woocommerce_api_keys WHERE key_id = %d", $key_id));
        // Return the key_id as secret reference (WC returns key_id, not raw secret)
        echo json_encode([
            'consumer_key' => $row->consumer_key,
            'consumer_secret' => 'Use key_id:' . $key_id . ' — secret was hashed by WC',
            'store_url' => 'https://olmeick-woocommerce.onrender.com',
            'user_id' => $admin_id,
            'key_id' => $key_id,
            'source' => 'wc_function'
        ]);
        exit;
    }
}

// Fallback: manual DB insert
$key = 'ck_' . bin2hex(random_bytes(20));
$secret = 'cs_' . bin2hex(random_bytes(20));
$hashed = hash('sha256', $secret);

$wpdb->insert($wpdb->prefix . 'woocommerce_api_keys', [
    'user_id' => $admin_id,
    'description' => 'OLMEICK Bridge Key',
    'consumer_key' => $key,
    'consumer_secret' => $hashed,
    'nonces' => serialize(['update' => '', 'delete' => '']),
    'permissions' => 'read_write',
]);
$key_id = $wpdb->insert_id;

echo json_encode([
    'consumer_key' => $key,
    'consumer_secret' => $secret,
    'store_url' => 'https://olmeick-woocommerce.onrender.com',
    'user_id' => $admin_id,
    'key_id' => $key_id,
    'source' => 'manual_db'
]);
