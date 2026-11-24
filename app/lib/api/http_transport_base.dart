/// Error categories raised by [HttpTransport] implementations.
enum HttpTransportErrorKind { network, tls, timeout, unsupportedWeb }

/// Low-level transport failure before a valid HTTP response was received.
class HttpTransportException implements Exception {
  const HttpTransportException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final HttpTransportErrorKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'HttpTransportException(${kind.name}): $message';
}

/// Immutable outgoing HTTP request.
class HttpTransportRequest {
  const HttpTransportRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 15),
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;
}

/// Immutable incoming HTTP response.
class HttpTransportResponse {
  const HttpTransportResponse({
    required this.statusCode,
    this.headers = const {},
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

/// Injectable HTTP transport contract so API calls work cross-platform with
/// zero external packages and are trivially testable with fake transports.
abstract class HttpTransport {
  bool get isSupported => true;

  Future<HttpTransportResponse> send(HttpTransportRequest request);
}
