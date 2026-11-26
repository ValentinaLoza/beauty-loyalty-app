import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_state.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean URLs such as /c/<token> instead of /#/c/<token>.
  // Cloudflare Pages serves this project as an SPA, so direct links work.
  usePathUrlStrategy();

  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigurationApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );

  final appState = AppState(Supabase.instance.client);

  // Draw immediately. The admin dashboard loads in the background and the
  // app shows a loading screen meanwhile, instead of a blank page.
  runApp(BeautyLoyaltyApp(appState: appState));
  unawaited(appState.initialize());
}

class _MissingConfigurationApp extends StatelessWidget {
  const _MissingConfigurationApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.settings_outlined, size: 54),
                  SizedBox(height: 18),
                  Text(
                    'Falta configurar Supabase',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Copiá config/example.json como config/local.json, '
                    'completá SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY, '
                    'y ejecutá Flutter con '
                    '--dart-define-from-file=config/local.json.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
