import 'package:flutter/material.dart';

typedef AppointmentSlotsLoader =
    Future<List<DateTime>> Function(DateTime day);

enum _SlotDialogAction {
  changeDay,
}

Future<DateTime?> pickAvailableAppointmentSlot(
  BuildContext context, {
  required AppointmentSlotsLoader loadSlots,
  DateTime? initialDate,
}) async {
  var suggestedDate = initialDate ?? DateTime.now().add(
    const Duration(days: 1),
  );

  while (context.mounted) {
    final now = DateTime.now();

    if (suggestedDate.isBefore(
      DateTime(now.year, now.month, now.day),
    )) {
      suggestedDate = DateTime(now.year, now.month, now.day);
    }

    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
      initialDate: suggestedDate,
      helpText: 'Elegí el día del turno',
      cancelText: 'Cancelar',
      confirmText: 'Ver horarios',
    );

    if (date == null || !context.mounted) return null;

    final slots = await _loadWithProgress(
      context,
      () => loadSlots(date),
    );

    if (!context.mounted) return null;

    if (slots == null) return null;

    final result = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elegí un horario'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(date),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sólo aparecen horarios libres. '
                  'La agenda trabaja en bloques de 30 minutos.',
                ),
                const SizedBox(height: 18),
                if (slots.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.event_busy_outlined),
                      title: Text('No quedan horarios disponibles'),
                      subtitle: Text(
                        'Elegí otro día para continuar.',
                      ),
                    ),
                  )
                else ...[
                  _SlotGroup(
                    title: 'Mañana',
                    slots: slots.where(
                      (slot) => slot.toLocal().hour < 12,
                    ).toList(),
                  ),
                  _SlotGroup(
                    title: 'Tarde',
                    slots: slots.where(
                      (slot) {
                        final hour = slot.toLocal().hour;
                        return hour >= 12 && hour < 18;
                      },
                    ).toList(),
                  ),
                  _SlotGroup(
                    title: 'Noche',
                    slots: slots.where(
                      (slot) => slot.toLocal().hour >= 18,
                    ).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _SlotDialogAction.changeDay,
            ),
            child: const Text('Cambiar día'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (result is DateTime) return result;
    if (result == _SlotDialogAction.changeDay) {
      suggestedDate = date;
      continue;
    }

    return null;
  }

  return null;
}

Future<List<DateTime>?> _loadWithProgress(
  BuildContext context,
  Future<List<DateTime>> Function() action,
) async {
  var finished = false;

  final future = action().whenComplete(() => finished = true);

  await Future<void>.delayed(const Duration(milliseconds: 120));

  if (finished) return future;

  if (!context.mounted) return null;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 16),
          Expanded(child: Text('Buscando horarios disponibles...')),
        ],
      ),
    ),
  );

  try {
    return await future;
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

class _SlotGroup extends StatelessWidget {
  const _SlotGroup({
    required this.title,
    required this.slots,
  });

  final String title;
  final List<DateTime> slots;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots
                .map(
                  (slot) => ActionChip(
                    avatar: const Icon(
                      Icons.schedule,
                      size: 17,
                    ),
                    label: Text(_formatTime(slot.toLocal())),
                    onPressed: () =>
                        Navigator.pop(context, slot),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatDate(DateTime value) {
  const weekdays = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  return '${weekdays[value.weekday - 1]} '
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}
