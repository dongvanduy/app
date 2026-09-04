abstract interface class AuthTokenProvider {
  String? get accessToken;

  Future<String?> refreshAccessToken();
}
