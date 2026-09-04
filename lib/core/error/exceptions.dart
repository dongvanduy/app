enum ApiFailureKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  server,
  invalidResponse,
  business,
  unknown,
}

class ServerException implements Exception {
  final String message;
  final int? statusCode;
  final ApiFailureKind kind;
  final List<String> invalidSerials;
  final Object? responseData;

  const ServerException(
    this.message, {
    this.statusCode,
    this.kind = ApiFailureKind.unknown,
    this.invalidSerials = const <String>[],
    this.responseData,
  });

  @override
  String toString() => message;
}

class ValidationException implements Exception {
  final String message;

  const ValidationException(this.message);

  @override
  String toString() => message;
}
