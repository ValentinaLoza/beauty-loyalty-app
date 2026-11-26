import 'dart:convert';
import 'dart:js_interop';

import 'config.dart';

@JS('bellamiaPushEnvironment')
external JSString _bellamiaPushEnvironment();

@JS('bellamiaPushSubscribe')
external JSPromise<JSString> _bellamiaPushSubscribe(
  JSString vapidPublicKey,
);

@JS('bellamiaSetClientPwaTarget')
external JSBoolean _bellamiaSetClientPwaTarget(
  JSString token,
);

@JS('bellamiaGetClientPwaTarget')
external JSString _bellamiaGetClientPwaTarget();


@JS('bellamiaSetAdminPwaTarget')
external JSBoolean _bellamiaSetAdminPwaTarget();


@JS('bellamiaPrepareClientInstall')
external JSBoolean _bellamiaPrepareClientInstall(
  JSString token,
);

@JS('bellamiaPrepareAdminInstall')
external JSBoolean _bellamiaPrepareAdminInstall();


class PushEnvironment {
  const PushEnvironment({
    required this.supported,
    required this.permission,
    required this.isIos,
    required this.isStandalone,
  });

  final bool supported;
  final String permission;
  final bool isIos;
  final bool isStandalone;

  factory PushEnvironment.fromMap(
    Map<String, dynamic> map,
  ) {
    return PushEnvironment(
      supported: map['supported'] as bool? ?? false,
      permission:
          map['permission'] as String? ?? 'unsupported',
      isIos: map['ios'] as bool? ?? false,
      isStandalone: map['standalone'] as bool? ?? false,
    );
  }
}

class PushSubscriptionPayload {
  const PushSubscriptionPayload({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
    required this.deviceLabel,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
  final String deviceLabel;

  factory PushSubscriptionPayload.fromMap(
    Map<String, dynamic> map,
  ) {
    return PushSubscriptionPayload(
      endpoint: map['endpoint'] as String? ?? '',
      p256dh: map['p256dh'] as String? ?? '',
      auth: map['auth'] as String? ?? '',
      deviceLabel:
          map['deviceLabel'] as String? ?? 'Web',
    );
  }

  Map<String, dynamic> toRpcParams() => {
        'p_endpoint': endpoint,
        'p_p256dh_key': p256dh,
        'p_auth_key': auth,
        'p_device_label': deviceLabel,
      };
}

class PushNotifications {
  const PushNotifications._();

  static void setClientPwaTarget(String token) {
    _bellamiaSetClientPwaTarget(token.toJS);
  }

  static String get clientPwaTarget =>
      _bellamiaGetClientPwaTarget().toDart;


  static void setAdminPwaTarget() {
    _bellamiaSetAdminPwaTarget();
  }


  static void prepareClientInstall(String token) {
    _bellamiaPrepareClientInstall(token.toJS);
  }

  static void prepareAdminInstall() {
    _bellamiaPrepareAdminInstall();
  }


  static bool get configured =>
      AppConfig.webPushVapidPublicKey.isNotEmpty;

  static PushEnvironment environment() {
    final raw = _bellamiaPushEnvironment().toDart;
    return PushEnvironment.fromMap(
      Map<String, dynamic>.from(
        jsonDecode(raw) as Map,
      ),
    );
  }

  static Future<PushSubscriptionPayload> subscribe() async {
    if (!configured) {
      throw Exception('VAPID_PUBLIC_KEY_MISSING');
    }

    final result = await _bellamiaPushSubscribe(
      AppConfig.webPushVapidPublicKey.toJS,
    ).toDart;

    return PushSubscriptionPayload.fromMap(
      Map<String, dynamic>.from(
        jsonDecode(result.toDart) as Map,
      ),
    );
  }

  static String friendlyError(Object error) {
    final text = error.toString();

    if (text.contains('IOS_HOME_SCREEN_REQUIRED')) {
      return 'En iPhone/iPad primero agregá la web a la pantalla '
          'de inicio y abrila desde ese ícono.';
    }

    if (text.contains('NOTIFICATION_PERMISSION_DENIED')) {
      return 'El permiso de notificaciones está bloqueado. '
          'Habilitalo desde la configuración del navegador.';
    }

    if (text.contains('PUSH_NOT_SUPPORTED')) {
      return 'Este navegador no admite notificaciones push.';
    }

    if (text.contains('VAPID_PUBLIC_KEY_MISSING')) {
      return 'Falta configurar la clave pública de notificaciones.';
    }

    return 'No se pudieron activar las notificaciones: $error';
  }
}
