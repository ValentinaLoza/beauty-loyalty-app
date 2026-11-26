import 'package:flutter/material.dart';

import '../app_state.dart';

/// "Copia de seguridad" card: last backup date and a download button.
class BackupCard extends StatefulWidget {
  const BackupCard({super.key, required this.appState});

  final AppState appState;

  /// Show a reminder on the dashboard after this many days without a backup.
  static const reminderDays = 14;

  /// True when there is data worth saving and no recent backup.
  static bool isDue(AppState appState) {
    final business = appState.business;
    if (business == null || appState.metrics.clientCount == 0) return false;
    final last = business.lastBackupAt;
    return last == null ||
        DateTime.now().difference(last).inDays >= reminderDays;
  }

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool _downloading = false;

  String _lastBackupText() {
    final last = widget.appState.business?.lastBackupAt?.toLocal();
    if (last == null) return 'Todavía no descargaste ninguna copia.';
    final days = DateTime.now().difference(last).inDays;
    final date = '${last.day.toString().padLeft(2, '0')}/'
        '${last.month.toString().padLeft(2, '0')}/${last.year}';
    if (days == 0) return 'Última copia: hoy ($date).';
    if (days == 1) return 'Última copia: ayer ($date).';
    return 'Última copia: hace $days días ($date).';
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    final ok = await widget.appState.downloadBackup();
    if (!mounted) return;
    setState(() => _downloading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Copia descargada. Guardala en Google Drive o mandátela por mail.'
              : widget.appState.errorMessage ?? 'No se pudo descargar la copia.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = BackupCard.isDue(widget.appState);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: due ? scheme.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.backup_outlined)),
              title: const Text(
                'Copia de seguridad',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(_lastBackupText()),
            ),
            const Text(
              'Descarga un archivo con todas las clientas, servicios, '
              'historial, beneficios y turnos. Guardalo fuera del celular '
              '(Google Drive o tu mail): si algún día se pierde la base, '
              'con ese archivo se recupera todo.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _downloading ? null : _download,
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: const Text('Descargar copia'),
            ),
          ],
        ),
      ),
    );
  }
}
