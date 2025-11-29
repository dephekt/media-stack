/**
 * Map Keycloak groups to Immich roles
 * - admin group → "admin" role
 * - family/photos group → "user" role
 * - no matching group → null (denies access)
 *
 * Runtime: Keycloak uses Nashorn 15.4 (ES5.1 + partial ES6 support)
 * Supports: let, const, arrow functions, template strings, for..of, etc.
 */

// Get user's groups
var groups = [];
var groupModels = user.getGroupsStream().toArray();
for (var i = 0; i < groupModels.length; i++) {
  groups.push(groupModels[i].getName());
}

// Map groups to Immich roles
if (groups.indexOf('admin') !== -1) {
  exports = 'admin';
} else if (groups.indexOf('family') !== -1 || groups.indexOf('photos') !== -1) {
  exports = 'user';
} else {
  exports = null;
}
