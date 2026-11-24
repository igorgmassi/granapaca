import 'http_transport_base.dart';

/// Web demo stub transport: per RF-63, the hosted browser demo must never
/// connect to external servers or real banks.
class WebStubHttpTransport extends HttpTransport {
  @override
  bool get isSupported => false;

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) {
    throw UnsupportedError(
      'Na demonstração web do GranaPaCá não são permitidas chamadas a '
      'servidores externos.',
    );
  }
}

HttpTransport createDefaultHttpTransport() => WebStubHttpTransport();
