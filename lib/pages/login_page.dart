import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscure = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    await widget.appState.login(emailController.text, passwordController.text);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFFFF4F8), Color(0xFFF8EDF3), Color(0xFFFFFBFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 36, offset: const Offset(0, 18)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                        child: Icon(Icons.auto_awesome, color: scheme.onPrimaryContainer, size: 30),
                      ),
                      const SizedBox(height: 20),
                      Text(AppConfig.fallbackTitle,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      const Text('Acceso de administración', style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 26),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: passwordController,
                        obscureText: obscure,
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      if (widget.appState.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(widget.appState.errorMessage!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: widget.appState.busy ? null : submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: widget.appState.busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Iniciar sesión'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Las clientas no necesitan usuario ni contraseña: cada una recibe su enlace privado de tarjeta.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
