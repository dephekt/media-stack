<?php

$dbFile = '/var/www/app/data/db.sqlite';

function env_value(string $name, string $default = ''): string
{
    $value = getenv($name);
    return $value === false || $value === '' ? $default : $value;
}

if (!is_file($dbFile)) {
    fwrite(STDERR, "Kanboard database not found: {$dbFile}\n");
    exit(1);
}

$clientSecret = env_value('KANBOARD_OAUTH2_CLIENT_SECRET');
if ($clientSecret === '') {
    fwrite(STDERR, "KANBOARD_OAUTH2_CLIENT_SECRET is required\n");
    exit(1);
}

$issuer = rtrim(env_value('KANBOARD_OAUTH2_ISSUER', 'https://auth.dephekt.net/realms/home'), '/');
$now = time();

$settings = [
    'application_url' => env_value('KANBOARD_APPLICATION_URL', 'https://kanban.ai.dephekt.net/'),
    'oauth2_client_id' => env_value('KANBOARD_OAUTH2_CLIENT_ID', 'kanboard'),
    'oauth2_client_secret' => $clientSecret,
    'oauth2_authorize_url' => "{$issuer}/protocol/openid-connect/auth",
    'oauth2_token_url' => "{$issuer}/protocol/openid-connect/token",
    'oauth2_user_api_url' => "{$issuer}/protocol/openid-connect/userinfo",
    'oauth2_scopes' => env_value('KANBOARD_OAUTH2_SCOPES', 'openid profile email'),
    'oauth2_key_username' => env_value('KANBOARD_OAUTH2_USERNAME_KEY', 'preferred_username'),
    'oauth2_key_name' => env_value('KANBOARD_OAUTH2_NAME_KEY', 'name'),
    'oauth2_key_email' => env_value('KANBOARD_OAUTH2_EMAIL_KEY', 'email'),
    'oauth2_key_user_id' => env_value('KANBOARD_OAUTH2_USER_ID_KEY', 'sub'),
    'oauth2_account_creation' => '1',
    'oauth2_email_domains' => env_value('KANBOARD_OAUTH2_EMAIL_DOMAINS', ''),
    'oauth2_key_groups' => env_value('KANBOARD_OAUTH2_GROUP_CLAIM', 'kanboard_roles'),
    'oauth2_key_group_filter' => env_value('KANBOARD_OAUTH2_GROUP_FILTER', 'kanboard-users,kanboard-admins'),
    'oauth2_custom_login_text' => env_value('KANBOARD_OAUTH2_LOGIN_TEXT', 'Login with Keycloak'),
];

$db = new PDO("sqlite:{$dbFile}");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$stmt = $db->prepare(
    'INSERT OR REPLACE INTO settings (option, value, changed_by, changed_on) VALUES (:option, :value, 0, :changed_on)'
);

foreach ($settings as $option => $value) {
    $stmt->execute([
        ':option' => $option,
        ':value' => $value,
        ':changed_on' => $now,
    ]);
}

fwrite(STDOUT, "Kanboard OAuth2 settings configured for {$settings['oauth2_client_id']}\n");
