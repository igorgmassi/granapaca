import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_transport_base.dart';

/// Native (Android, iOS, Linux, macOS, Windows) HTTP transport built on
/// `dart:io`'s [HttpClient] with zero third-party packages.
class IoHttpTransport extends HttpTransport {
  IoHttpTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) async {
    final client = _clientFactory();
    client.connectionTimeout = request.timeout;
    try {
      final ioRequest = await client
          .openUrl(request.method, request.uri)
          .timeout(request.timeout);

      request.headers.forEach((key, value) {
        ioRequest.headers.set(key, value);
      });

      if (request.body != null) {
        final encoded = utf8.encode(request.body!);
        ioRequest.headers.contentLength = encoded.length;
        ioRequest.add(encoded);
      }

      final ioResponse = await ioRequest.close().timeout(request.timeout);
      final body = await ioResponse
          .transform(utf8.decoder)
          .join()
          .timeout(request.timeout);

      final responseHeaders = <String, String>{};
      ioResponse.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });

      return HttpTransportResponse(
        statusCode: ioResponse.statusCode,
        headers: responseHeaders,
        body: body,
      );
    } on HandshakeException catch (error) {
      throw HttpTransportException(
        kind: HttpTransportErrorKind.tls,
        message: 'TLS handshake failed',
        cause: error,
      );
    } on TlsException catch (error) {
      throw HttpTransportException(
        kind: HttpTransportErrorKind.tls,
        message: 'TLS error',
        cause: error,
      );
    } on TimeoutException catch (error) {
      throw HttpTransportException(
        kind: HttpTransportErrorKind.timeout,
        message: 'Request timed out',
        cause: error,
      );
    } on SocketException catch (error) {
      throw HttpTransportException(
        kind: HttpTransportErrorKind.network,
        message: 'Network error',
        cause: error,
      );
    } on HttpException catch (error) {
      throw HttpTransportException(
        kind: HttpTransportErrorKind.network,
        message: 'HTTP transport error',
        cause: error,
      );
    } finally {
      client.close(force: true);
    }
  }
}

HttpTransport createDefaultHttpTransport() => IoHttpTransport();
