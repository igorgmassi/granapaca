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
    PaymentMethod? paymentMethod,
    bool? isAtypical,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      if (category != null) 'category': category.name,
      if (essentiality != null) 'essentiality': essentiality.name,
      if (kind != null) 'kind': txKindToApiString(kind),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (paymentMethod != null) 'paymentMethod': paymentMethod.name,
      'isAtypical': ?isAtypical,
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

  /// RF-44: records a physical-cash expense on the self-hosted server
  /// (`POST /api/v1/transactions/cash`) with idempotency via [clientMutationId].
  Future<({Transaction transaction, String? serverUuid})> createCashTransaction({
    required DateTime date,
    required String description,
    required int amountCents,
    TxKind kind = TxKind.expense,
    SpendingCategory? category,
    Essentiality? essentiality,
    List<String> tags = const [],
    String? clientMutationId,
  }) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/transactions/cash',
      body: {
        'occurredOn': date.toIso8601String().substring(0, 10),
        'description': description.trim(),
        'amountCents': -amountCents.abs(),
        'kind': txKindToApiString(kind),
        if (category != null) 'category': category.name,
        if (essentiality != null) 'essentiality': essentiality.name,
        if (tags.isNotEmpty) 'tags': tags,
        if (clientMutationId != null && clientMutationId.trim().isNotEmpty)
          'clientMutationId': clientMutationId.trim(),
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível registrar o gasto em dinheiro no servidor.',
    );
    final map = _decodeJsonMap(response.body);
    final rawId = map['id']?.toString();
    final tx = transactionFromJson(map);
    return (
      transaction: tx,
      serverUuid: (rawId != null && rawId.isNotEmpty) ? rawId : null,
    );
  }

  /// RF-23: replaces tags attached to a transaction
  /// (`PUT /api/v1/transactions/{id}/tags`).
  Future<void> updateTransactionTags(
    String transactionId,
    List<String> tags,
  ) async {
    final response = await _sendAuthorized(
      method: 'PUT',
      path: '/api/v1/transactions/$transactionId/tags',
      body: {'tags': tags},
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível atualizar as tags da transação.',
    );
  }

  /// RN-24: replaces transaction splits enforcing exact-cent signed total on
  /// server (`PUT /api/v1/transactions/{id}/splits` with `parts` payload).
  Future<void> replaceTransactionSplits({
    required String transactionId,
    required int transactionAmountCents,
    required List<TxSplit> splits,
  }) async {
    final sign = transactionAmountCents < 0 ? -1 : 1;
    final response = await _sendAuthorized(
      method: 'PUT',
      path: '/api/v1/transactions/$transactionId/splits',
      body: {
        'parts': [
          for (final s in splits)
            {
              'description': s.description,
              'amountCents': sign * s.amountCents.abs(),
              if (s.category != null) 'category': s.category!.name,
              if (s.essentiality != null) 'essentiality': s.essentiality!.name,
            },
        ],
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível salvar a divisão da transação.',
    );
  }

  /// Applies bulk adjustments across multiple transaction UUIDs
  /// (`POST /api/v1/transactions/bulk-adjustments`).
  Future<void> applyBulkAdjustments({
    required List<String> transactionIds,
    SpendingCategory? category,
    Essentiality? essentiality,
    PaymentMethod? paymentMethod,
    bool? isAtypical,
    String? reason,
  }) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/transactions/bulk-adjustments',
      body: {
        'transactionIds': transactionIds,
        if (category != null) 'category': category.name,
        if (essentiality != null) 'essentiality': essentiality.name,
        if (paymentMethod != null) 'paymentMethod': paymentMethod.name,
        'isAtypical': ?isAtypical,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível aplicar a correção em lote.',
    );
  }

  /// Creates or updates a monthly category budget on the server
  /// (`PUT /api/v1/planning/budgets`).
  Future<Budget> upsertBudget(Budget budget) async {
    final thresholdPercent = (budget.alertThreshold * 100).round().clamp(1, 100);
    final response = await _sendAuthorized(
      method: 'PUT',
      path: '/api/v1/planning/budgets',
      body: {
        'category': budget.category.name,
        'monthLimitCents': budget.limitCents,
        'alertThresholdPercent': thresholdPercent,
        'isActive': true,
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível salvar o orçamento.',
    );
    return budgetFromApiJson(_decodeJsonMap(response.body), fallback: budget);
  }

  /// Removes a monthly budget on the server
  /// (`DELETE /api/v1/planning/budgets/{id}`).
  Future<void> deleteBudget(String budgetId) async {
    final response = await _sendAuthorized(
      method: 'DELETE',
      path: '/api/v1/planning/budgets/$budgetId',
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível remover o orçamento.',
    );
  }

  /// Creates a financial goal on the server (`POST /api/v1/planning/goals`).
  Future<Goal> createGoal(Goal goal) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/planning/goals',
      body: {
        'name': goal.name,
        'targetCents': goal.targetCents,
        'currentCents': goal.currentCents,
        if (goal.targetDate != null)
          'targetDate': goal.targetDate!.toIso8601String().substring(0, 10),
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível criar a meta financeira.',
    );
    return goalFromApiJson(_decodeJsonMap(response.body), fallback: goal);
  }

  /// Records a contribution toward an existing financial goal
  /// (`PATCH /api/v1/planning/goals/{id}` with `addCents`).
  Future<Goal> contributeGoal(String goalId, int amountCents) async {
    final response = await _sendAuthorized(
      method: 'PATCH',
      path: '/api/v1/planning/goals/$goalId',
      body: {'addCents': amountCents},
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível registrar o aporte na meta.',
    );
    return goalFromApiJson(_decodeJsonMap(response.body));
  }

  /// Removes a financial goal on the server
  /// (`DELETE /api/v1/planning/goals/{id}`).
  Future<void> deleteGoal(String goalId) async {
    final response = await _sendAuthorized(
      method: 'DELETE',
      path: '/api/v1/planning/goals/$goalId',
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível remover a meta financeira.',
    );
  }

  /// Registers a custom spending alert threshold rule on the server
  /// (`POST /api/v1/planning/alert-rules`).
  Future<SpendingAlertRule> createSpendingAlertRule(
    SpendingAlertRule rule,
  ) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/planning/alert-rules',
      body: {
        'expression': rule.rawExpression,
        if (rule.category != null) 'category': rule.category!.name,
        if (rule.keyword != null && rule.keyword!.trim().isNotEmpty)
          'merchantKeyword': rule.keyword!.trim(),
        'limitCents': rule.thresholdCents,
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível criar o alerta de gasto.',
    );
    return spendingAlertRuleFromApiJson(
      _decodeJsonMap(response.body),
      fallback: rule,
    );
  }

  /// Removes a custom spending alert rule on the server
  /// (`DELETE /api/v1/planning/alert-rules/{id}`).
  Future<void> deleteSpendingAlertRule(String ruleId) async {
    final response = await _sendAuthorized(
      method: 'DELETE',
      path: '/api/v1/planning/alert-rules/$ruleId',
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível remover a regra de alerta.',
    );
  }

  /// Saves receipt item-analysis consent on the server
  /// (`PUT /api/v1/receipts/consent`).
  Future<void> updateReceiptConsent({
    required bool itemAnalysisAccepted,
    bool dietaryNotesAccepted = false,
  }) async {
    final response = await _sendAuthorized(
      method: 'PUT',
      path: '/api/v1/receipts/consent',
      body: {
        'itemAnalysisAccepted': itemAnalysisAccepted,
        'dietaryNotesAccepted': dietaryNotesAccepted,
      },
    );
    _throwIfError(
      response,
      defaultMessage:
          'Não foi possível salvar o consentimento de leitura de notas.',
    );
  }

  /// Submits an NFC-e XML or SEFAZ QR URL for server parsing and linking
  /// (`POST /api/v1/receipts/nfce/parse`).
  Future<Map<String, dynamic>> submitNfceReceipt({
    required String rawInput,
    String? transactionId,
    bool save = true,
  }) async {
    final trimmed = rawInput.trim();
    final isXml = trimmed.startsWith('<');
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/receipts/nfce/parse',
      body: {
        if (isXml) 'xml': trimmed else 'qrUrl': trimmed,
        if (transactionId != null && transactionId.trim().isNotEmpty)
          'transactionId': transactionId.trim(),
        'save': save,
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível processar a nota fiscal no servidor.',
    );
    return _decodeJsonMap(response.body);
  }

  /// Imports an OFX or CSV bank statement on the server
  /// (`POST /api/v1/imports/ofx` or `POST /api/v1/imports/csv`).
  Future<Map<String, dynamic>> importStatement({
    required String format,
    required String content,
    required String institutionName,
    required String accountName,
    AccountKind accountKind = AccountKind.checking,
  }) async {
    final normalizedFormat = format.toLowerCase().trim() == 'ofx'
        ? 'ofx'
        : 'csv';
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/imports/$normalizedFormat',
      body: {
        'institutionName': institutionName.trim(),
        'accountName': accountName.trim(),
        'accountKind': accountKindToApiString(accountKind),
        'content': content,
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível importar o arquivo de extrato.',
    );
    return _decodeJsonMap(response.body);
  }

  /// Downloads an RFC 4180 CSV export from the server
  /// (`GET /api/v1/export/transactions.csv`).
  Future<String> exportTransactionsCsv({DateTime? from, DateTime? to}) async {
    final response = await _sendAuthorized(
      method: 'GET',
      path: '/api/v1/export/transactions.csv',
      queryParameters: {
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
      },
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível exportar o arquivo CSV.',
    );
    return response.body;
  }

  /// Downloads a full JSON backup from the server
  /// (`GET /api/v1/export/backup.json`).
  Future<String> exportBackupJson() async {
    final response = await _sendAuthorized(
      method: 'GET',
      path: '/api/v1/export/backup.json',
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível gerar o backup JSON.',
    );
    return response.body;
  }

  /// Sends a read-only question to Paçoca assistant on the self-hosted server
  /// (`POST /api/v1/assistant/chat`).
  Future<AssistantMessage> askAssistant({
    required String question,
    required DateTime month,
  }) async {
    final monthParam =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/assistant/chat',
      body: {'message': question.trim(), 'month': monthParam},
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível consultar a Paçoca no servidor agora.',
    );
    final map = _decodeJsonMap(response.body);
    final rawCited =
        (map['numbersCited'] as List<dynamic>?) ??
        (map['citedFigures'] as List<dynamic>?) ??
        const [];
    final citedFigures = <String>[];
    for (final entry in rawCited) {
      if (entry is Map<String, dynamic>) {
        final label = (entry['label'] as String?)?.trim() ?? '';
        final formatted = (entry['formatted'] as String?)?.trim() ?? '';
        if (label.isNotEmpty && formatted.isNotEmpty) {
          citedFigures.add('$label: $formatted');
        } else if (formatted.isNotEmpty) {
          citedFigures.add(formatted);
        } else if (label.isNotEmpty) {
          citedFigures.add(label);
        }
      } else {
        final text = entry.toString().trim();
        if (text.isNotEmpty) citedFigures.add(text);
      }
    }
    return AssistantMessage(
      id: (map['messageId'] ??
              map['id'] ??
              'pacoca-${DateTime.now().microsecondsSinceEpoch}')
          .toString(),
      isUser: false,
      text: (map['content'] ?? map['answer'] ?? map['text'] ?? '').toString(),
      timestamp:
          DateTime.tryParse(
            (map['createdAt'] as String?) ??
                (map['timestamp'] as String?) ??
                '',
          ) ??
          DateTime.now(),
      periodLabel:
          (map['periodUsed'] as String?) ?? (map['periodLabel'] as String?),
      citedFigures: List.unmodifiable(citedFigures),
    );
  }

  /// Saves BYOK AI provider configuration on the self-hosted server
  /// (`PUT /api/v1/assistant/provider`).
  Future<AiProviderConfig> updateAiProviderConfig(
    AiProviderConfig config, {
    String? apiKey,
    bool clearApiKey = false,
  }) async {
    final isOllama = config.provider == AiProviderKind.ollama;
    final trimmedBaseUrl = config.endpointUrl.trim();
    final trimmedApiKey = apiKey?.trim() ?? '';
    final response = await _sendAuthorized(
      method: 'PUT',
      path: '/api/v1/assistant/provider',
      body: {
        'provider': config.provider.name,
        'model': config.provider == AiProviderKind.none
            ? ''
            : config.model.trim(),
        if (isOllama && trimmedBaseUrl.isNotEmpty) 'baseUrl': trimmedBaseUrl,
        if (trimmedApiKey.isNotEmpty) 'apiKey': trimmedApiKey,
        if (clearApiKey) 'clearApiKey': true,
      },
    );
    _throwIfError(
      response,
      defaultMessage:
          'Não foi possível salvar a configuração do provedor de IA.',
    );
    if (response.body.trim().isEmpty) {
      return config;
    }
    final map = _decodeJsonMap(response.body);
    return aiProviderConfigFromApiJson(map, fallback: config);
  }

  /// Confirms or rejects a low-confidence Paçoca categorization suggestion on
  /// the server (`POST /api/v1/assistant/suggestions/{id}/decide`).
  Future<void> decideAssistantSuggestion({
    required String suggestionId,
    required bool confirm,
  }) async {
    final response = await _sendAuthorized(
      method: 'POST',
      path: '/api/v1/assistant/suggestions/$suggestionId/decide',
      body: {'action': confirm ? 'confirm' : 'reject'},
    );
    _throwIfError(
      response,
      defaultMessage: 'Não foi possível registrar sua decisão na sugestão.',
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
