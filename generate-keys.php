<?php
/**
 * OLMEICK — Génère des clés API WooCommerce
 * Stocke consumer_key hashé (hmac-sha256) et consumer_secret en clair.
 */
header('Content-Type: application/json');
error_reporting(0);

$sock = '/var/run/mysqld/mysqld.sock';
$db = new mysqli('localhost', 'olmeick', 'olmeick_wc_2026', 'woocommerce', 3306, $sock);

if ($db->connect_error) {
    echo json_encode(['error' => 'DB: ' . $db->connect_error]);
    exit;
}

// Vérifier si des clés existent déjà
$existing = $db->query("SELECT key_id FROM wp_woocommerce_api_keys ORDER BY key_id DESC LIMIT 1");
if ($existing && $existing->num_rows > 0) {
    $row = $existing->fetch_assoc();
    $r2 = $db->query("SELECT consumer_key, consumer_secret FROM wp_woocommerce_api_keys WHERE key_id = " . (int)$row['key_id']);
    $key_row = $r2->fetch_assoc();
    echo json_encode([
        'consumer_key' => $key_row['consumer_key'],
        'consumer_secret' => $key_row['consumer_secret'],
        'key_id' => (int)$row['key_id'],
        'source' => 'existing'
    ]);
    exit;
}

// Générer nouvelles clés
$ck = 'ck_' . bin2hex(random_bytes(20));
$cs = 'cs_' . bin2hex(random_bytes(20));

// WooCommerce utilise hash_hmac('sha256', $key, 'wc-api') pour stocker le consumer_key
// Le consumer_secret est stocké EN CLAIR
$ck_hashed = hash_hmac('sha256', $ck, 'wc-api');
$ts = date('Y-m-d H:i:s');

$sql = $db->prepare("INSERT INTO wp_woocommerce_api_keys (user_id, description, permissions, consumer_key, consumer_secret, nonces, date_created) VALUES (?, ?, ?, ?, ?, ?, ?)");
$uid = 1;
$desc = 'OLMEICK Bridge';
$perm = 'read_write';
$nonces = '';
$sql->bind_param('issssss', $uid, $desc, $perm, $ck_hashed, $cs, $nonces, $ts);
$sql->execute();
$key_id = $db->insert_id;

if ($key_id > 0) {
    // Sauvegarder dans un fichier JSON pour api-keys.php
    $json = json_encode([
        'consumer_key' => $ck,
        'consumer_secret' => $cs,
        'store_url' => 'https://olmeick-woocommerce.onrender.com',
        'key_id' => $key_id
    ]);
    file_put_contents('/var/www/html/wc-api-keys.json', $json);
    chmod('/var/www/html/wc-api-keys.json', 0644);

    echo json_encode([
        'consumer_key' => $ck,
        'consumer_secret' => $cs,
        'key_id' => $key_id,
        'source' => 'generated'
    ]);
} else {
    echo json_encode(['error' => 'Insert failed', 'sql_error' => $db->error]);
}
