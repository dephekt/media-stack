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

$legacyGroups = array_filter(
    array_map('trim', explode(',', env_value('KANBOARD_LEGACY_GROUP_EXTERNAL_IDS', 'kanboard-users,kanboard-admins')))
);

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
    'oauth2_key_groups' => env_value('KANBOARD_OAUTH2_GROUP_CLAIM', ''),
    'oauth2_key_group_filter' => env_value('KANBOARD_OAUTH2_GROUP_FILTER', ''),
    'oauth2_custom_login_text' => env_value('KANBOARD_OAUTH2_LOGIN_TEXT', 'Login with Keycloak'),
];

function placeholders(array $values): string
{
    return implode(',', array_fill(0, count($values), '?'));
}

function cleanup_legacy_groups(PDO $db, array $externalIds): int
{
    if (empty($externalIds)) {
        return 0;
    }

    $stmt = $db->prepare(
        'SELECT g.id, g.name, g.external_id, COUNT(pg.project_id) AS project_refs
        FROM groups g
        LEFT JOIN project_has_groups pg ON pg.group_id = g.id
        WHERE g.external_id IN ('.placeholders($externalIds).')
        GROUP BY g.id, g.name, g.external_id'
    );
    $stmt->execute($externalIds);
    $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $blocked = array_filter($groups, static fn (array $group): bool => (int) $group['project_refs'] > 0);
    if (!empty($blocked)) {
        $names = implode(', ', array_map(static fn (array $group): string => $group['name'], $blocked));
        throw new RuntimeException("Legacy OAuth groups still have project permissions: {$names}");
    }

    $groupIds = array_map(static fn (array $group): int => (int) $group['id'], $groups);
    if (empty($groupIds)) {
        return 0;
    }

    $db->prepare('DELETE FROM group_has_users WHERE group_id IN ('.placeholders($groupIds).')')->execute($groupIds);
    $db->prepare('DELETE FROM groups WHERE id IN ('.placeholders($groupIds).')')->execute($groupIds);

    return count($groupIds);
}

$db = new PDO("sqlite:{$dbFile}");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$db->beginTransaction();

try {
    $removedGroups = cleanup_legacy_groups($db, $legacyGroups);

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

    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    fwrite(STDERR, $e->getMessage()."\n");
    exit(1);
}

fwrite(STDOUT, "Kanboard OAuth2 settings configured for {$settings['oauth2_client_id']}\n");
if ($removedGroups > 0) {
    fwrite(STDOUT, "Removed {$removedGroups} legacy Kanboard OAuth group(s)\n");
}
