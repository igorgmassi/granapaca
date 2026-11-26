import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/api/granapaca_api_client.dart';
import 'package:granapaca/api/http_transport.dart';
import 'package:granapaca/main.dart';
import 'package:granapaca/screens/app_lock_screen.dart';
import 'package:granapaca/screens/onboarding_screen.dart';
import 'package:granapaca/screens/server_auth_screen.dart';
import 'package:granapaca/security/app_lock.dart';
import 'package:granapaca/state/app_state.dart';
import 'package:granapaca/state/preferences_store.dart';
import 'package:granapaca/theme/grana_theme.dart';
import 'package:granapaca/theme/pacoca_mascot.dart';

class _StubTransport extends HttpTransport {
  _StubTransport(this._handler);

  final Future<HttpTransportResponse> Function(HttpTransportRequest) _handler;

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) =>
      _handler(request);
}

Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Toca Editorial theme tokens & Option B brand mark', () {
    test('light and dark schemes and typography match Toca Editorial tokens', () {
      expect(granaLightColorScheme.surface, const Color(0xFFFAF8F5));
      expect(granaLightColorScheme.primary, const Color(0xFFA84C19));
      expect(granaLightColorScheme.onSurface, const Color(0xFF231C16));
      expect(granaLightColorScheme.surfaceDim, const Color(0xFFEAE4DC));
      expect(granaLightColorScheme.surfaceBright, const Color(0xFFFFFFFF));
      expect(granaLightColorScheme.inverseSurface, const Color(0xFF2F2721));
      expect(granaLightColorScheme.onInverseSurface, const Color(0xFFF5F1EC));
      expect(granaLightColorScheme.inversePrimary, const Color(0xFFE5965C));
      expect(granaLightColorScheme.surfaceTint, const Color(0xFFA84C19));
      expect(GranaTokens.light.mata, const Color(0xFF1D6B48));

      expect(granaDarkColorScheme.surface, const Color(0xFF14110F));
      expect(granaDarkColorScheme.surfaceContainerLow, const Color(0xFF1E1A17));
      expect(granaDarkColorScheme.primary, const Color(0xFFE5965C));
      expect(granaDarkColorScheme.onSurface, const Color(0xFFF5F1EC));
      expect(granaDarkColorScheme.surfaceDim, const Color(0xFF14110F));
      expect(granaDarkColorScheme.surfaceBright, const Color(0xFF342E29));
      expect(granaDarkColorScheme.inverseSurface, const Color(0xFFF5F1EC));
      expect(granaDarkColorScheme.onInverseSurface, const Color(0xFF231C16));
      expect(granaDarkColorScheme.inversePrimary, const Color(0xFFA84C19));
      expect(granaDarkColorScheme.surfaceTint, const Color(0xFFE5965C));
      expect(GranaTokens.dark.mata, const Color(0xFF62C493));

      final lightTheme = granaLightTheme();
      expect(lightTheme.textTheme.displayMedium?.fontFamily, 'Plus Jakarta Sans');
      expect(lightTheme.textTheme.displayMedium?.fontSize, 36);
      expect(lightTheme.textTheme.headlineSmall?.fontFamily, 'Plus Jakarta Sans');
      expect(lightTheme.textTheme.headlineSmall?.fontSize, 18);
      expect(lightTheme.textTheme.titleLarge?.fontFamily, 'Inter');
      expect(lightTheme.textTheme.titleLarge?.fontSize, 20);
      expect(lightTheme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(lightTheme.textTheme.bodyMedium?.fontSize, 14);
      expect(lightTheme.textTheme.labelSmall?.fontFamily, 'Inter');
      expect(lightTheme.textTheme.labelSmall?.fontSize, 11);

      expect(GranaTokens.light.valorDestaque.fontSize, 38);
      expect(GranaTokens.light.valorDestaque.fontWeight, FontWeight.w700);
      expect(GranaTokens.light.valorGrande.fontSize, 24);
      expect(GranaTokens.light.valorGrande.fontWeight, FontWeight.w600);
      expect(GranaTokens.light.valorLinha.fontSize, 16);
      expect(GranaTokens.light.valorLinha.fontWeight, FontWeight.w600);
      expect(GranaTokens.light.falaPacoca.fontFamily, 'Plus Jakarta Sans');
      expect(GranaTokens.light.falaPacoca.fontSize, 16);
      expect(GranaTokens.light.falaPacoca.fontWeight, FontWeight.w500);
    });

    testWidgets('GranaPacaLogo and RestingPacaMark render in Light and Dark', (
      tester,
    ) async {
      for (final theme in [granaLightTheme(), granaDarkTheme()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: Column(
                children: [
                  GranaPacaLogo(showTagline: true),
                  RestingPacaMark(size: 56),
                  EditorialStepDots(total: 5, currentIndex: 2),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GranaPacaLogo), findsOneWidget);
        expect(find.byType(RestingPacaMark), findsOneWidget);
        expect(find.byType(EditorialStepDots), findsOneWidget);
      }
    });
  });

  group('AnimatedPacocaMascot — all 5 account creation animations', () {
    testWidgets(
      'reacts cleanly across mode, email, password, peek, 2FA, error, and completion',
      (tester) async {
        var ownerConfigured = false;
        final transport = _StubTransport((req) async {
          switch (req.uri.path) {
            case '/api/v1/server-info':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'app': 'GranaPaCa',
                  'version': '2.0.0',
                  'apiVersion': 1,
                  'ownerConfigured': ownerConfigured,
                  'providerMode': 'pluggy',
                }),
              );
            case '/api/v1/auth/setup':
              ownerConfigured = true;
              return HttpTransportResponse(
                statusCode: 201,
                body: jsonEncode({
                  'ownerId': 'own-1',
                  'householdId': 'hh-1',
                  'email': 'bia@exemplo.local',
                  'displayName': 'Bia',
                }),
              );
            case '/api/v1/auth/login':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'status': 'totp_setup_required',
                  'pendingToken': 'pending-tok-1',
                }),
              );
            case '/api/v1/auth/totp/setup':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'manualKey': 'JBSWY3DPEHPK3PXP',
                  'otpauthUri':
                      'otpauth://totp/GranaPaCa:bia@exemplo.local?secret=JBSWY3DPEHPK3PXP&issuer=GranaPaCa',
                }),
              );
            case '/api/v1/auth/totp/confirm':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'status': 'authenticated',
                  'accessToken': 'tok-access',
                  'refreshToken': 'tok-refresh',
                  'expiresAt': '2026-12-29T12:00:00Z',
                  'sessionId': 'sess-1',
                  'owner': {
                    'id': 'own-1',
                    'householdId': 'hh-1',
                    'email': 'bia@exemplo.local',
                    'displayName': 'Bia',
                  },
                  'recoveryCodes': ['AAAA-1111', 'BBBB-2222'],
                }),
              );
            default:
              return const HttpTransportResponse(statusCode: 404, body: '{}');
          }
        });

        final state = AppState(
          preferencesStore: InMemoryPreferencesStore(),
          apiClient: GranaPaCaApiClient(transport: transport),
        );

        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              theme: granaLightTheme(),
              home: const ServerAuthScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        AnimatedPacocaMascot readMascot() =>
            tester.widget<AnimatedPacocaMascot>(
              find.byKey(const Key('auth_pacoca_mascot')),
            );

        // 1. Directional mode selection gaze
        expect(readMascot().mood, PacocaMood.welcome);
        expect(readMascot().gazeX, lessThan(0));

        await _scrollIntoView(tester, find.byKey(const Key('mode_demo_card')));
        await tester.tap(find.byKey(const Key('mode_demo_card')));
        await tester.pumpAndSettle();
        expect(readMascot().gazeX, greaterThan(0));

        // Validate server -> enters owner account creation
        await _scrollIntoView(
          tester,
          find.byKey(const Key('server_url_field')),
        );
        await tester.enterText(
          find.byKey(const Key('server_url_field')),
          'https://toca.exemplo.ts.net',
        );
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.trackingInput);

        await _scrollIntoView(
          tester,
          find.byKey(const Key('server_validate_button')),
        );
        await tester.tap(find.byKey(const Key('server_validate_button')));
        await tester.pumpAndSettle();

        // 2. Email / Name eye tracking
        await _scrollIntoView(
          tester,
          find.byKey(const Key('setup_name_field')),
        );
        await tester.tap(find.byKey(const Key('setup_name_field')));
        await tester.enterText(
          find.byKey(const Key('setup_name_field')),
          'Bia',
        );
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.trackingInput);
        final shortGaze = readMascot().gazeX;

        await tester.tap(find.byKey(const Key('setup_email_field')));
        await tester.enterText(
          find.byKey(const Key('setup_email_field')),
          'bia.silva@exemplo.com.br',
        );
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.trackingInput);
        expect(readMascot().gazeX, greaterThan(shortGaze));

        // 3. Password focus -> covers both eyes!
        await _scrollIntoView(
          tester,
          find.byKey(const Key('setup_password_field')),
        );
        await tester.tap(find.byKey(const Key('setup_password_field')));
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.coveringEyes);

        // 3b. Tap "Mostrar senha" -> shy one-paw peek!
        await tester.tap(
          find.byKey(const Key('setup_password_visibility_toggle')),
        );
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.peekingPassword);

        // Hide password again -> back to covering eyes
        await tester.tap(
          find.byKey(const Key('setup_password_visibility_toggle')),
        );
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.coveringEyes);

        // Enter strong password & mismatched confirmation -> calmError MUST
        // appear immediately even while the password field remains focused!
        await tester.enterText(
          find.byKey(const Key('setup_password_field')),
          'SenhaForte!2026',
        );
        await _scrollIntoView(
          tester,
          find.byKey(const Key('setup_confirm_password_field')),
        );
        await tester.tap(find.byKey(const Key('setup_confirm_password_field')));
        await tester.enterText(
          find.byKey(const Key('setup_confirm_password_field')),
          'OutraSenha!2026',
        );
        await tester.pump();
        expect(readMascot().mood, PacocaMood.coveringEyes);

        await _scrollIntoView(
          tester,
          find.byKey(const Key('setup_owner_submit_button')),
        );
        await tester.tap(find.byKey(const Key('setup_owner_submit_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
        expect(readMascot().mood, PacocaMood.calmError);
        expect(readMascot().errorSignal, greaterThan(0));

        // Typing in the focused confirmation password field clears the error
        // immediately and returns Paçoca to coveringEyes.
        await _scrollIntoView(
          tester,
          find.byKey(const Key('setup_confirm_password_field')),
        );
        await tester.enterText(
          find.byKey(const Key('setup_confirm_password_field')),
          'SenhaForte!2026',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth_error_banner')), findsNothing);
        expect(readMascot().mood, PacocaMood.coveringEyes);

        await _scrollIntoView(
          tester,
          find.byKey(const Key('setup_owner_submit_button')),
        );
        await tester.tap(find.byKey(const Key('setup_owner_submit_button')));
        await tester.pumpAndSettle();

        await _scrollIntoView(
          tester,
          find.byKey(const Key('login_submit_button')),
        );
        await tester.tap(find.byKey(const Key('login_submit_button')));
        await tester.pumpAndSettle();

        // 4. Security shield step: short code triggers calmError, then typing
        // clears the error and restores securityShield with digit progress.
        expect(readMascot().mood, PacocaMood.securityShield);
        await _scrollIntoView(
          tester,
          find.byKey(const Key('totp_confirm_code_field')),
        );
        await tester.enterText(
          find.byKey(const Key('totp_confirm_code_field')),
          '123',
        );
        await _scrollIntoView(
          tester,
          find.byKey(const Key('totp_confirm_button')),
        );
        await tester.tap(find.byKey(const Key('totp_confirm_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
        expect(readMascot().mood, PacocaMood.calmError);

        await _scrollIntoView(
          tester,
          find.byKey(const Key('totp_confirm_code_field')),
        );
        await tester.enterText(
          find.byKey(const Key('totp_confirm_code_field')),
          '481920',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth_error_banner')), findsNothing);
        expect(readMascot().mood, PacocaMood.securityShield);
        expect(readMascot().securityProgress, closeTo(1.0, 0.01));

        // 5. Complete 2FA -> celebration jump + 3 coin dots
        await _scrollIntoView(
          tester,
          find.byKey(const Key('totp_confirm_button')),
        );
        await tester.tap(find.byKey(const Key('totp_confirm_button')));
        await tester.pumpAndSettle();
        expect(readMascot().mood, PacocaMood.celebrating);
      },
    );

    testWidgets('respects MediaQuery disableAnimations across every mood', (
      tester,
    ) async {
      for (final mood in PacocaMood.values) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              theme: granaDarkTheme(),
              home: Scaffold(
                body: Center(
                  child: AnimatedPacocaMascot(
                    mood: mood,
                    gazeX: 0.5,
                    securityProgress: 0.67,
                    errorSignal: 1,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(AnimatedPacocaMascot), findsOneWidget);
      }
    });

    testWidgets('OnboardingScreen shows Paçoca peek preview and celebration', (
      tester,
    ) async {
      final state = AppState(preferencesStore: InMemoryPreferencesStore());
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: granaLightTheme(),
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_pacoca_mascot')), findsOneWidget);
      expect(find.byType(GranaPacaLogo), findsOneWidget);

      // Advance to Server (step 2) and Login (step 3)
      await tester.tap(find.byKey(const Key('onboarding_continue_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_continue_button')));
      await tester.pumpAndSettle();

      AnimatedPacocaMascot mascot() => tester.widget<AnimatedPacocaMascot>(
        find.byKey(const Key('onboarding_pacoca_mascot')),
      );
      expect(mascot().mood, PacocaMood.coveringEyes);

      await _scrollIntoView(
        tester,
        find.byKey(const Key('demo_password_peek_toggle')),
      );
      await tester.tap(find.byKey(const Key('demo_password_peek_toggle')));
      await tester.pumpAndSettle();
      expect(mascot().mood, PacocaMood.peekingPassword);
    });

    testWidgets(
      'AppLockScreen animates Paçoca shield and calm error on wrong PIN',
      (tester) async {
        final lock = AppLockController();
        await lock.configurePin('123456');

        await tester.pumpWidget(
          MaterialApp(
            theme: granaDarkTheme(),
            home: AppLockScreen(controller: lock),
          ),
        );
        await tester.pumpAndSettle();

        AnimatedPacocaMascot mascot() => tester.widget<AnimatedPacocaMascot>(
          find.byKey(const Key('app_lock_pacoca_mascot')),
        );
        expect(mascot().mood, PacocaMood.securityShield);

        for (final d in ['9', '9', '9', '9', '9', '9']) {
          await tester.tap(find.byKey(Key('pin_key_$d')));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(mascot().mood, PacocaMood.calmError);
        expect(mascot().errorSignal, 1);
      },
    );

    testWidgets(
      'HomeScreen displays compact Toca Editorial Paçoca insight strip with falaPacoca',
      (tester) async {
        await tester.pumpWidget(
          GranaPaCaApp(
            preferencesStore: InMemoryPreferencesStore(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('home_pacoca_insight_card')),
          findsOneWidget,
        );
        final insightText = tester.widget<Text>(
          find.byKey(const Key('home_pacoca_insight_text')),
        );
        expect(insightText.style?.fontFamily, 'Plus Jakarta Sans');
        expect(insightText.style?.fontSize, 16);
        expect(insightText.style?.fontWeight, FontWeight.w500);
      },
    );

    testWidgets(
      'ServerAuthScreen shows calmError immediately while login 2FA field is '
      'focused and recovers to securityShield when editing',
      (tester) async {
        final transport = _StubTransport((req) async {
          if (req.uri.path == '/api/v1/server-info') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'app': 'GranaPaCa',
                'version': '2.0.0',
                'apiVersion': 1,
                'ownerConfigured': true,
                'providerMode': 'pluggy',
              }),
            );
          }
          if (req.uri.path == '/api/v1/auth/login') {
            return HttpTransportResponse(
              statusCode: 401,
              body: jsonEncode({'message': 'Código 2FA inválido.'}),
            );
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final state = AppState(
          preferencesStore: InMemoryPreferencesStore(),
          apiClient: GranaPaCaApiClient(transport: transport),
        );

        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              theme: granaLightTheme(),
              home: const ServerAuthScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        AnimatedPacocaMascot readMascot() =>
            tester.widget<AnimatedPacocaMascot>(
              find.byKey(const Key('auth_pacoca_mascot')),
            );

        await _scrollIntoView(
          tester,
          find.byKey(const Key('server_url_field')),
        );
        await tester.enterText(
          find.byKey(const Key('server_url_field')),
          'https://toca.exemplo.ts.net',
        );
        await _scrollIntoView(
          tester,
          find.byKey(const Key('server_validate_button')),
        );
        await tester.tap(find.byKey(const Key('server_validate_button')));
        await tester.pumpAndSettle();

        await _scrollIntoView(
          tester,
          find.byKey(const Key('login_email_field')),
        );
        await tester.enterText(
          find.byKey(const Key('login_email_field')),
          'bia@exemplo.local',
        );
        await _scrollIntoView(
          tester,
          find.byKey(const Key('login_password_field')),
        );
        await tester.enterText(
          find.byKey(const Key('login_password_field')),
          'SenhaForte!2026',
        );
        await _scrollIntoView(
          tester,
          find.byKey(const Key('login_totp_field')),
        );
        await tester.tap(find.byKey(const Key('login_totp_field')));
        await tester.enterText(
          find.byKey(const Key('login_totp_field')),
          '000000',
        );
        await tester.pump();
        expect(readMascot().mood, PacocaMood.securityShield);

        // Submit while login_totp_field stays focused -> calmError immediately!
        await _scrollIntoView(
          tester,
          find.byKey(const Key('login_submit_button')),
        );
        await tester.tap(find.byKey(const Key('login_submit_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth_error_banner')), findsOneWidget);
        expect(readMascot().mood, PacocaMood.calmError);

        // Editing the 2FA code clears the error and restores securityShield.
        await _scrollIntoView(
          tester,
          find.byKey(const Key('login_totp_field')),
        );
        await tester.enterText(
          find.byKey(const Key('login_totp_field')),
          '123456',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth_error_banner')), findsNothing);
        expect(readMascot().mood, PacocaMood.securityShield);
        expect(readMascot().securityProgress, closeTo(1.0, 0.01));
      },
    );
  });
}
