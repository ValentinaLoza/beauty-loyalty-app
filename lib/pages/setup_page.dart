import 'package:flutter/material.dart';

import '../app_state.dart';

class BusinessSetupPage extends StatefulWidget {
  const BusinessSetupPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<BusinessSetupPage> createState() => _BusinessSetupPageState();
}

class _BusinessSetupPageState extends State<BusinessSetupPage> {
  final nameController = TextEditingController();
  final colorController = TextEditingController(text: '#8F5E78');

  @override
  void dispose() {
    nameController.dispose();
    colorController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (nameController.text.trim().isEmpty) return;
    await widget.appState.createBusiness(
      name: nameController.text,
      primaryColorHex: colorController.text,
    );
  }

  Future<void> restore() async {
    final result = await widget.appState.restoreBackupFromFile();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copia restaurada: ${result['clients']} clientas, '
          '${result['service_records']} servicios y '
          '${result['appointments']} turnos.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(Icons.storefront, size: 48),
                      const SizedBox(height: 16),
                      Text('Configurá el emprendimiento',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      const Text(
                        'Esto se hace una sola vez. El nombre y color se pueden cambiar después desde el panel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Nombre del emprendimiento *', prefixIcon: Icon(Icons.storefront_outlined)),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: colorController,
                        decoration: const InputDecoration(labelText: 'Color principal', helperText: 'Formato: #8F5E78', prefixIcon: Icon(Icons.palette_outlined)),
                      ),
                      if (widget.appState.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(widget.appState.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: widget.appState.busy ? null : save,
                        child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Crear emprendimiento')),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        '¿Ya tenías el negocio cargado en otro proyecto? '
                        'Podés recuperarlo con el archivo de copia de seguridad.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: widget.appState.busy ? null : restore,
                        icon: const Icon(Icons.restore),
                        label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Restaurar copia de seguridad')),
                      ),
                      const SizedBox(height: 8),
                      TextButton(onPressed: widget.appState.logout, child: const Text('Cerrar sesión')),
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
