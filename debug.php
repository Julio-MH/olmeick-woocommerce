<?php
header('Content-Type: application/json');
$_SERVER['PHP_SELF'] = '/wp-admin/admin-ajax.php';
$_SERVER['HTTPS'] = 'on';
require_once('/var/www/html/wp-load.php');
global $wpdb;

$keys = $wpdb->get_results("SELECT key_id, user_id, consumer_key, LEFT(consumer_secret,30) as secret_prefix, permissions, nonces FROM {$wpdb->prefix}woocommerce_api_keys ORDER BY key_id DESC LIMIT 3");
$users = $wpdb->get_results("SELECT ID, user_login, user_email FROM {$wpdb->users} LIMIT 3");
echo json_encode(['keys' => $keys, 'users' => $users], JSON_PRETTY_PRINT);
