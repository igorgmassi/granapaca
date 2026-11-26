import 'dart:convert';

import '../finance/model.dart';
import '../finance/taxonomy.dart';
import 'api_models.dart';
import 'http_transport.dart';

/// Cross-platform, zero-dependency HTTP client for the GranaPaCá self-hosted
/// `/api/v1/*` backend (RF-01, RF-02, RF-03, RF-12, RF-13, RF-14, RF-21).
class GranaPaCaApiClient {
  GranaPaCaApiClient({
    HttpTransport? transport,
    this._baseUrl,
    AuthTokens? initialTokens,
    this.onTokensChanged,
  }) : _transport = transport ?? createDefaultHttpTransport(),
       _tokens = initialTokens;

  final HttpTransport _transport;
  Uri? _baseUrl;
  AuthTokens? _tokens;
  Future<AuthTokens>? _ongoingRefresh;

  /// Callback triggered whenever access/refresh tokens rotate or are cleared.
  void Function(AuthTokens? tokens)? onTokensChanged;

  bool get isTransportSupported => _transport.isSupported;
  Uri? get baseUrl => _baseUrl;
  AuthTokens? get tokens => _tokens;
  bool get isAuthenticated => _tokens != null && _tokens!.accessToken.isNotEmpty;

  void setBaseUrl(Uri? uri) {
    _baseUrl = uri;
  }

  void setTokens(AuthTokens? tokens) {
    _tokens = tokens;
    onTokensChanged?.call(tokens);
  }

  static bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase().trim();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]';
  }

  /// Validates and normalizes a user-provided server URL (RF-01).
  ///
  /// Enforces HTTPS for all remote hosts; plain HTTP is allowed exclusively
  /// for local loopback addresses (`localhost`, `127.0.0.1`, `::1`).
  static Uri normalizeServerUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const ApiException(
        code: 'invalid_url',
        message: 'Informe o endereço do seu servidor GranaPaCá.',
      );
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        !(parsed.scheme == 'https' || parsed.scheme == 'http') ||
        parsed.host.isEmpty) {
      throw const ApiException(
        code: 'invalid_url',
        message:
            'Use um endereço completo começando com https:// '
            '(por exemplo, https://financas.minha-rede.ts.net).',
      );
    }
    if (parsed.scheme == 'http' && !_isLoopbackHost(parsed.host)) {
      throw const ApiException(
        code: 'insecure_http_not_allowed',
        message:
            'Use https:// para conectar a servidores fora deste aparelho. '
            'http:// só é permitido para localhost, 127.0.0.1 ou ::1.',
      );
    }
    final normalizedPath = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    return parsed.replace(
      path: normalizedPath,
      query: null,
      fragment: null,
    );
  }

  Uri _buildUri(
    String path, {
    Uri? overrideBaseUrl,
    Map<String, String>? queryParameters,
  }) {
    final base = overrideBaseUrl ?? _baseUrl;
    if (base == null) {
      throw const ApiException(
        code: 'server_not_configured',
        message: 'Configure primeiro o endereço do seu servidor.',
      );
    }
    final cleanBasePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final cleanSegment = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '$cleanBasePath$cleanSegment',
      queryParameters: queryParameters != null && queryParameters.isNotEmpty
          ? queryParameters
          : null,
    );
  }

  /// RF-01: verifies that [baseUrl] points to a compatible GranaPaCá instance.
  Future<ServerInfo> fetchServerInfo(Uri baseUrl) async {
    final response = await _sendRaw(
      method: 'GET',
      uri: _buildUri('/api/v1/server-info', overrideBaseUrl: baseUrl),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        code: 'not_granapaca_server',
        message:
            'Esse endereço respondeu, mas não parece ser uma instância do '
            'GranaPaCá. Confira a URL informada.',
        statusCode: response.statusCode,
      );
    }
    final map = _decodeJsonMap(
      response.body,
      fallbackMessage:
          'Esse endereço não devolveu uma resposta válida do GranaPaCá.',
    );
    final info = ServerInfo.fromJson(map);
    if (info.app != 'GranaPaCa') {
      throw const ApiException(
        code: 'not_granapaca_server',
        message:
            'O servidor encontrado não é uma instância do GranaPaCá. '
            'Confira o endereço digitado.',
      );
    }
    if (info.apiVersion != 1) {
      throw const ApiException(
        code: 'incompatible_api_version',
        message:
            'A versão desse servidor não é compatível com esta versão do app. '
            'Atualize o app ou o servidor para continuar.',
      );
    }
    return info;
  }

  /// RF-02: creates the single owner account on a fresh instance.
  Future<SetupOwnerResult> setupOwner({
    required String email,
    required String displayName,
    required String password,
    String? householdName,
    String? timezone,
  }) async {
    final response = await _sendRaw(
      method: 'POST',
      uri: _buildUri('/api/v1/auth/setup'),
      body: {
        'email': email.trim(),
        'displayName': displayName.trim(),
        'password': password,
        'householdName': householdName,
        'timezone': timezone,
      },
    );
    _throwIfError(
      response,
      defaultMessage:
          'Não foi possível criar a conta proprietária neste momento.',
    );
    final map = _decodeJsonMap(response.body);
    return SetupOwnerResult.fromJson(map);
  }

  /// RF-03: authenticates with password + optional TOTP or recovery code.
  Future<LoginResult> login({
    required String email,
    required String password,
    String? totpCode,
    String? recoveryCode,
    String? deviceName,
  }) async {
    final response = await _sendRaw(
      method: 'POST',
      uri: _buildUri('/api/v1/auth/login'),
      body: {
        'email': email.trim(),
        'password': password,
        if (totpCode != null && totpCode.trim().isNotEmpty)
          'totpCode': totpCode.trim(),
        if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
          'recoveryCode': recoveryCode.trim(),
        if (deviceName != null && deviceName.trim().isNotEmpty)
          'deviceName': deviceName.trim(),
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'E-mail, senha ou código de verificação inválidos.',
    );
    final map = _decodeJsonMap(response.body);
    final status = (map['status'] as String?) ?? '';
    if (status == 'totp_setup_required') {
      final pendingToken = (map['pendingToken'] as String?) ?? '';
      if (pendingToken.isEmpty) {
        throw const ApiException(
          code: 'invalid_response',
          message: 'Não foi possível iniciar a configuração do autenticador.',
        );
      }
      return LoginResult.totpSetupRequired(pendingToken);
    }
    if (status == 'authenticated') {
      final tokens = AuthTokens.fromJson(map);
      setTokens(tokens);
      return LoginResult.authenticated(tokens);
    }
    throw const ApiException(
      code: 'unexpected_login_status',
      message: 'Resposta inesperada do servidor ao entrar.',
    );
  }

  /// RF-03: begins mandatory TOTP 2FA enrollment for a pending login.
  Future<TotpSetupData> beginTotpSetup(String pendingToken) async {
    final response = await _sendRaw(
      method: 'POST',
      uri: _buildUri('/api/v1/auth/totp/setup'),
      body: {'pendingToken': pendingToken},
    );
    _throwIfError(
      response,
      defaultMessage:
          'Não foi possível gerar a chave do autenticador. Tente entrar novamente.',
    );
    return TotpSetupData.fromJson(_decodeJsonMap(response.body));
  }

  /// RF-03: verifies the first 6-digit TOTP code, enables 2FA, and returns
  /// the 8 one-time recovery codes alongside session tokens.
  Future<TotpConfirmResult> confirmTotp(
    String pendingToken,
    String code,
  ) async {
    final response = await _sendRaw(
      method: 'POST',
      uri: _buildUri('/api/v1/auth/totp/confirm'),
      body: {'pendingToken': pendingToken, 'totpCode': code.trim()},
    );
    _throwIfError(
      response,
      defaultMessage:
          'Código do autenticador inválido. Confira o código de 6 dígitos e tente novamente.',
    );
    final result = TotpConfirmResult.fromJson(_decodeJsonMap(response.body));
    setTokens(result.tokens);
    return result;
  }

  /// ADR-019: rotates refresh + access tokens.
  Future<AuthTokens> refresh(String refreshToken) async {
    final inFlight = _ongoingRefresh;
    if (inFlight != null) return inFlight;

    final future = _performRefresh(refreshToken);
    _ongoingRefresh = future;
    try {
      return await future;
    } finally {
      if (identical(_ongoingRefresh, future)) {
        _ongoingRefresh = null;
      }
    }
  }

  Future<AuthTokens> _performRefresh(String refreshToken) async {
    final response = await _sendRaw(
      method: 'POST',
      uri: _buildUri('/api/v1/auth/refresh'),
      body: {'refreshToken': refreshToken},
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      setTokens(null);
      throw const ApiException(
        code: 'session_expired',
        message: 'Sua sessão expirou. Entre novamente para continuar.',
        statusCode: 401,
        isUnauthorized: true,
      );
    }
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível renovar a sua sessão.',
    );
    final rotated = AuthTokens.fromJson(_decodeJsonMap(response.body));
    setTokens(rotated);
    return rotated;
  }

  /// RF-03: revokes the current session on the server and clears local tokens.
  Future<void> logout() async {
    final current = _tokens;
    try {
      if (current != null && current.accessToken.isNotEmpty) {
        await _sendRaw(
          method: 'POST',
          uri: _buildUri('/api/v1/auth/logout'),
          bearerToken: current.accessToken,
        );
      }
    } catch (_) {
      // Always clear local session even if the server is temporarily offline.
    } finally {
      setTokens(null);
    }
  }

  /// RF-03: lists active device sessions for the authenticated owner.
  Future<List<ActiveSession>> listSessions() async {
    final response = await _sendAuthorized(
      method: 'GET',
      path: '/api/v1/auth/sessions',
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível carregar as sessões ativas.',
    );
    final decoded = _decodeJsonDynamic(response.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map<String, dynamic>
              ? (decoded['items'] as List<dynamic>? ?? const [])
              : const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(ActiveSession.fromJson)
        .toList(growable: false);
  }

  /// RF-03: revokes a specific session by id.
  Future<void> revokeSession(String sessionId) async {
    final response = await _sendAuthorized(
      method: 'DELETE',
      path: '/api/v1/auth/sessions/$sessionId',
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível encerrar a sessão selecionada.',
    );
  }

  /// RF-12 & RF-13: triggers bank synchronization on the server.
  Future<SyncConnectionsResult> syncConnections() async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/connections/sync',
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível sincronizar suas conexões bancárias.',
    );
    return SyncConnectionsResult.fromJson(_decodeJsonMap(response.body));
  }

  /// RF-12: registers a Pluggy item ID with the self-hosted backend.
  Future<BankConnectionInfo> registerPluggyConnection(
    String itemId, {
    String? institutionName,
    String? brandColor,
  }) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/connections/pluggy',
      body: {
        'externalItemId': itemId.trim(),
        if (institutionName != null && institutionName.trim().isNotEmpty)
          'institutionName': institutionName.trim(),
        if (brandColor != null && brandColor.trim().isNotEmpty)
          'brandColor': brandColor.trim(),
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível vincular essa conexão do Meu Pluggy.',
    );
    return BankConnectionInfo.fromJson(_decodeJsonMap(response.body));
  }

  /// RF-14: fetches all configured bank connections and their health/expiry.
  Future<List<BankConnectionInfo>> fetchConnections() async {
    final response = await _sendAuthorized(
      method: 'GET',
      path: '/api/v1/connections',
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível carregar as conexões bancárias.',
    );
    final decoded = _decodeJsonDynamic(response.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map<String, dynamic>
              ? (decoded['items'] as List<dynamic>? ?? const [])
              : const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(BankConnectionInfo.fromJson)
        .toList(growable: false);
  }

  /// RF-21: incremental delta synchronization using an opaque server cursor.
  Future<SyncChangesResponse> fetchSyncChanges({String? cursor}) async {
    final response = await _sendAuthorized(
      method: 'GET',
      path: '/api/v1/sync/changes',
      queryParameters: (cursor != null && cursor.isNotEmpty)
          ? {'cursor': cursor}
          : null,
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível buscar as atualizações do servidor.',
    );
    return SyncChangesResponse.fromJson(_decodeJsonMap(response.body));
  }

  /// RF-24 & RF-31: persists manual transaction adjustments on the backend
  /// (`POST /api/v1/transactions/{id}/adjustments`).
  Future<List<TxAdjustment>> applyTransactionAdjustments({
    required String transactionId,
    SpendingCategory? category,
    Essentiality? essentiality,
    TxKind? kind,
    String? description,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      if (category != null) 'category': category.name,
      if (essentiality != null) 'essentiality': essentiality.name,
      if (kind != null) 'kind': txKindToApiString(kind),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/transactions/$transactionId/adjustments',
      body: body,
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível salvar a correção no servidor.',
    );
    final map = _decodeJsonMap(response.body);
    final fallbackTxId = stableTransactionId(transactionId);
    final applied = (map['appliedAdjustments'] as List<dynamic>?) ?? const [];
    return applied
        .whereType<Map<String, dynamic>>()
        .map((j) => adjustmentFromJson(j, fallbackTxId: fallbackTxId))
        .toList(growable: false);
  }

  /// RF-25: appends an undo record on the backend
  /// (`POST /api/v1/transactions/{id}/adjustments/{adjustmentId}/undo`).
  Future<TxAdjustment?> undoTransactionAdjustment({
    required String transactionId,
    required String adjustmentId,
  }) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/transactions/$transactionId/adjustments/$adjustmentId/undo',
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível desfazer o ajuste no servidor.',
    );
    final map = _decodeJsonMap(response.body);
    final raw = map['adjustment'];
    if (raw is Map<String, dynamic>) {
      return adjustmentFromJson(
        raw,
        fallbackTxId: stableTransactionId(transactionId),
      );
    }
    return null;
  }

  /// RF-26 & RF-31: creates a user classification rule on the backend
  /// (`POST /api/v1/rules`).
  Future<UserRule> createRule({
    required String matchMerchant,
    required String name,
    required String explanation,
    SpendingCategory? category,
    Essentiality? essentiality,
  }) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/rules',
      body: {
        'name': name,
        'explanation': explanation,
        'matchMerchant': matchMerchant,
        if (category != null) 'category': category.name,
        if (essentiality != null) 'essentiality': essentiality.name,
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível salvar a regra no servidor.',
    );
    return userRuleFromJson(_decodeJsonMap(response.body));
  }

  /// RF-27: activates or deactivates a classification rule on the backend
  /// (`PATCH /api/v1/rules/{id}`).
  Future<UserRule> updateRuleActive({
    required String ruleId,
    required bool isActive,
  }) async {
    final response = await _sendAuthorized(
      method: 'PATCH',
      path: '/api/v1/rules/$ruleId',
      body: {'isActive': isActive},
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível atualizar a regra no servidor.',
    );
    return userRuleFromJson(_decodeJsonMap(response.body));
  }

  /// RF-27: removes a classification rule on the backend
  /// (`DELETE /api/v1/rules/{id}`).
  Future<void> deleteRule(String ruleId) async {
    final response = await _sendAuthorized(
      method: 'DELETE',
      path: '/api/v1/rules/$ruleId',
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível remover a regra no servidor.',
    );
  }

  Future<HttpTransportResponse> _sendAuthorized({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final current = _tokens;
    if (current == null || current.accessToken.isEmpty) {
      throw const ApiException(
        code: 'unauthenticated',
        message: 'Entre na sua instância para continuar.',
        statusCode: 401,
        isUnauthorized: true,
      );
    }

    final uri = _buildUri(path, queryParameters: queryParameters);
    final firstResponse = await _sendRaw(
      method: method,
      uri: uri,
      body: body,
      bearerToken: current.accessToken,
    );
    if (firstResponse.statusCode != 401) {
      return firstResponse;
    }

    if (current.refreshToken.isEmpty) {
      setTokens(null);
      throw const ApiException(
        code: 'session_expired',
        message: 'Sua sessão expirou. Entre novamente para continuar.',
        statusCode: 401,
        isUnauthorized: true,
      );
    }

    // Automatic single refresh & retry on 401 (ADR-019).
    final refreshed = await refresh(current.refreshToken);
    return _sendRaw(
      method: method,
      uri: uri,
      body: body,
      bearerToken: refreshed.accessToken,
    );
  }

  Future<HttpTransportResponse> _sendRaw({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
    };
    try {
      return await _transport.send(
        HttpTransportRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
      );
    } on UnsupportedError {
      throw const ApiException(
        code: 'web_demo_only',
        message:
            'No modo demonstração pela web não há conexão com servidores '
            'externos.',
      );
    } on HttpTransportException catch (error) {
      switch (error.kind) {
        case HttpTransportErrorKind.tls:
          throw const ApiException(
            code: 'tls_error',
            message:
                'Não foi possível validar a conexão segura com esse servidor. '
                'Confira o certificado HTTPS da sua instância.',
          );
        case HttpTransportErrorKind.timeout:
          throw const ApiException(
            code: 'timeout',
            message:
                'O servidor demorou demais para responder. Confira se a sua '
                'instância está ligada e tente novamente.',
            isOffline: true,
          );
        case HttpTransportErrorKind.unsupportedWeb:
          throw const ApiException(
            code: 'web_demo_only',
            message:
                'No modo demonstração pela web não há conexão com servidores '
                'externos.',
          );
        case HttpTransportErrorKind.network:
          throw const ApiException(
            code: 'network_error',
            message:
                'Não conseguimos alcançar esse servidor. Verifique a conexão '
                'com a internet ou com a sua rede privada (como Tailscale).',
            isOffline: true,
          );
      }
    }
  }

  void _throwIfError(
    HttpTransportResponse response, {
    required String defaultMessage,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String code = 'http_${response.statusCode}';
    String message = defaultMessage;
    bool fullResyncRequired = false;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        // Supports both RFC 9457 ProblemDetails ({title, detail, type, code,
        // fullResyncRequired}) and legacy {error, message} payloads.
        final problemCode = decoded['code'];
        final serverCode = decoded['error'];
        final problemType = decoded['type'];
        final problemDetail = decoded['detail'];
        final problemTitle = decoded['title'];
        final serverMsg = decoded['message'];

        if (problemCode is String && problemCode.trim().isNotEmpty) {
          code = problemCode.trim();
        } else if (serverCode is String && serverCode.isNotEmpty) {
          code = serverCode;
        } else if (problemType is String &&
            problemType.trim().isNotEmpty &&
            problemType != 'about:blank') {
          code = problemType.trim();
        }

        if (problemDetail is String && problemDetail.trim().isNotEmpty) {
          message = problemDetail.trim();
        } else if (serverMsg is String && serverMsg.trim().isNotEmpty) {
          message = serverMsg.trim();
        } else if (problemTitle is String && problemTitle.trim().isNotEmpty) {
          message = problemTitle.trim();
        } else if (serverCode is String && serverCode.contains(' ')) {
          message = serverCode;
        }

        if (decoded['fullResyncRequired'] == true) {
          fullResyncRequired = true;
        }
      }
    } catch (_) {
      // Keep human-friendly default message if response is not JSON.
    }

    throw ApiException(
      code: code,
      message: message,
      statusCode: response.statusCode,
      isUnauthorized: response.statusCode == 401,
      fullResyncRequired: fullResyncRequired,
    );
  }

  Map<String, dynamic> _decodeJsonMap(
    String body, {
    String fallbackMessage = 'O servidor enviou uma resposta inesperada.',
  }) {
    final decoded = _decodeJsonDynamic(body, fallbackMessage: fallbackMessage);
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException(code: 'invalid_json', message: fallbackMessage);
  }

  dynamic _decodeJsonDynamic(
    String body, {
    String fallbackMessage = 'O servidor enviou uma resposta inesperada.',
  }) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      return jsonDecode(body);
    } catch (_) {
      throw ApiException(code: 'invalid_json', message: fallbackMessage);
    }
  }
}
