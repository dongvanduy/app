class AuthUser {
  final int userId;
  final String username;
  final String role;
  final String allowedAreas;
  final List<String> permissions;
  final String fullName;
  final String chineseName;
  final String email;
  final String department;
  final String cft;

  const AuthUser({
    required this.userId,
    required this.username,
    required this.role,
    required this.allowedAreas,
    required this.permissions,
    required this.fullName,
    required this.chineseName,
    required this.email,
    required this.department,
    required this.cft,
  });

  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  bool hasPermission(String permission) => permissions.contains(permission);
}
