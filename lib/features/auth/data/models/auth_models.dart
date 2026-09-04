import '../../../../core/error/exceptions.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';

class AuthUserModel extends AuthUser {
  const AuthUserModel({
    required super.userId,
    required super.username,
    required super.role,
    required super.allowedAreas,
    required super.permissions,
    required super.fullName,
    required super.chineseName,
    required super.email,
    required super.department,
    required super.cft,
  });

  factory AuthUserModel.fromJson(Map<String, dynamic> json) {
    final rawUserId = json['userId'];
    final userId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    final username = json['username']?.toString().trim() ?? '';

    if (userId == null || username.isEmpty) {
      throw const ServerException(
        'The authentication server returned an invalid user profile.',
        kind: ApiFailureKind.invalidResponse,
      );
    }

    final rawPermissions = json['permissions'];
    return AuthUserModel(
      userId: userId,
      username: username,
      role: json['role']?.toString() ?? '',
      allowedAreas: json['allowedAreas']?.toString() ?? '',
      permissions: rawPermissions is List
          ? rawPermissions.map((value) => value.toString()).toList()
          : const <String>[],
      fullName: json['fullName']?.toString() ?? '',
      chineseName: json['chineseName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      cft: json['cft']?.toString() ?? '',
    );
  }

  factory AuthUserModel.fromEntity(AuthUser user) {
    return AuthUserModel(
      userId: user.userId,
      username: user.username,
      role: user.role,
      allowedAreas: user.allowedAreas,
      permissions: List<String>.of(user.permissions),
      fullName: user.fullName,
      chineseName: user.chineseName,
      email: user.email,
      department: user.department,
      cft: user.cft,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'userId': userId,
        'username': username,
        'role': role,
        'allowedAreas': allowedAreas,
        'permissions': permissions,
        'fullName': fullName,
        'chineseName': chineseName,
        'email': email,
        'department': department,
        'cft': cft,
      };
}

class AuthSessionModel extends AuthSession {
  const AuthSessionModel({
    required super.tokenType,
    required super.accessToken,
    required super.refreshToken,
    required AuthUserModel super.user,
  });

  @override
  AuthUserModel get user => super.user as AuthUserModel;

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    final accessToken = json['accessToken']?.toString().trim() ?? '';
    final refreshToken = json['refreshToken']?.toString().trim() ?? '';
    final rawUser = json['user'];

    if (accessToken.isEmpty ||
        refreshToken.isEmpty ||
        rawUser is! Map<String, dynamic>) {
      throw const ServerException(
        'The authentication server returned an invalid token response.',
        kind: ApiFailureKind.invalidResponse,
      );
    }

    return AuthSessionModel(
      tokenType: json['tokenType']?.toString().trim().isNotEmpty == true
          ? json['tokenType'].toString().trim()
          : 'Bearer',
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: AuthUserModel.fromJson(rawUser),
    );
  }

  factory AuthSessionModel.fromEntity(AuthSession session) {
    return AuthSessionModel(
      tokenType: session.tokenType,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      user: AuthUserModel.fromEntity(session.user),
    );
  }

  AuthSessionModel copyWithUser(AuthUser user) {
    return AuthSessionModel(
      tokenType: tokenType,
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: AuthUserModel.fromEntity(user),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tokenType': tokenType,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'user': user.toJson(),
      };
}
