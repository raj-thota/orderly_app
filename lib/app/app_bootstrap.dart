import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:orderly_app/core/services/notification_service.dart';

const List<String> _requiredEnvKeys = <String>[
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
];

class AppBootstrapState {
  final bool isReady;
  final String message;

  const AppBootstrapState._({required this.isReady, required this.message});

  const AppBootstrapState.ready()
    : this._(isReady: true, message: 'Closr is ready.');

  const AppBootstrapState.missingConfiguration([
    String message =
        'Supabase keys are missing. Pass SUPABASE_URL and '
        'SUPABASE_ANON_KEY with --dart-define or update '
        'assets/env/default.env for local development.',
  ]) : this._(isReady: false, message: message);

  const AppBootstrapState.failure([
    String message =
        'Closr could not finish startup. Check your Supabase settings and try '
        'again.',
  ]) : this._(isReady: false, message: message);
}

class AppBootstrapper {
  static Future<AppBootstrapState> bootstrap() async {
    try {
      await dotenv.load(
        fileName: 'assets/env/default.env',
        isOptional: true,
        mergeWith: _compileTimeEnv,
      );

      if (!dotenv.isEveryDefined(_requiredEnvKeys)) {
        return const AppBootstrapState.missingConfiguration();
      }

      await Supabase.initialize(
        url: dotenv.get('SUPABASE_URL'),
        anonKey: dotenv.get('SUPABASE_ANON_KEY'),
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );

      await NotificationService.init();

      return const AppBootstrapState.ready();
    } catch (_) {
      return const AppBootstrapState.failure();
    }
  }

  static Map<String, String> get _compileTimeEnv {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    return <String, String>{
      if (supabaseUrl.isNotEmpty) 'SUPABASE_URL': supabaseUrl,
      if (supabaseAnonKey.isNotEmpty) 'SUPABASE_ANON_KEY': supabaseAnonKey,
    };
  }
}
