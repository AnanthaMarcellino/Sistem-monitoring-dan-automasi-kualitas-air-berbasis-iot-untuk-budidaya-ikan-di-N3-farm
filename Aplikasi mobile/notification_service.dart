import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  final Map<String, DateTime> _lastNotificationTime = {};

  static const Duration _phCooldown = Duration(minutes: 5);
  static const Duration _temperatureCooldown = Duration(minutes: 5);
  static const Duration _turbidityCooldown = Duration(minutes: 5);
  static const Duration _foodLevelCooldown = Duration(seconds: 0);
  static const Duration _relayCooldown = Duration(minutes: 3);
  static const Duration _pumpDosingCooldown = Duration(minutes: 2);

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Request permission untuk Android 13+
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
  }

  bool _canSendNotification(String notificationId, Duration cooldown) {
    final lastTime = _lastNotificationTime[notificationId];
    if (lastTime == null) return true;

    final now = DateTime.now();
    final difference = now.difference(lastTime);
    return difference >= cooldown;
  }

  void _updateLastNotificationTime(String notificationId) {
    _lastNotificationTime[notificationId] = DateTime.now();
  }

  Future<void> showPhAlert({
    required double phValue,
    required bool isHigh,
  }) async {
    const String notificationId = 'ph_warning';

    if (!_canSendNotification(notificationId, _phCooldown)) {
      print('⏱️ pH notification skipped - cooldown active');
      return;
    }

    final String title = isHigh ? '⚠️ pH Terlalu Basa!' : '⚠️ pH Terlalu Asam!';
    final String body = isHigh
        ? 'pH air terlalu basa!!! Nilai pH: ${phValue.toStringAsFixed(2)}\nSegera cek kondisi air kolam.'
        : 'pH air terlalu asam!!! Nilai pH: ${phValue.toStringAsFixed(2)}\nSegera cek kondisi air kolam.';

    await _showNotification(
      id: 1,
      title: title,
      body: body,
      payload: 'ph_warning',
    );

    _updateLastNotificationTime(notificationId);
  }

  Future<void> showTemperatureAlert({
    required double tempValue,
    required bool isHigh,
  }) async {
    const String notificationId = 'temp_warning';

    if (!_canSendNotification(notificationId, _temperatureCooldown)) {
      print('⏱️ Temperature notification skipped - cooldown active');
      return;
    }

    final String title =
    isHigh ? '🌡️ Suhu Terlalu Panas!' : '🌡️ Suhu Terlalu Dingin!';
    final String body = isHigh
        ? 'Suhu air terlalu panas!!! Suhu: ${tempValue.toStringAsFixed(1)}°C\nSegera cek sistem pendingin.'
        : 'Suhu air terlalu dingin!!! Suhu: ${tempValue.toStringAsFixed(1)}°C\nSegera cek pemanas air.';

    await _showNotification(
      id: 2,
      title: title,
      body: body,
      payload: 'temperature_warning',
    );

    _updateLastNotificationTime(notificationId);
  }

  Future<void> showTurbidityAlert({
    required double ntuValue,
  }) async {
    const String notificationId = 'turbidity_warning';

    if (!_canSendNotification(notificationId, _turbidityCooldown)) {
      print('⏱️ Turbidity notification skipped - cooldown active');
      return;
    }

    const String title = '💧 Air Terlalu Keruh!';
    final String body =
        'Air terlalu keruh!!! NTU: ${ntuValue.toStringAsFixed(1)}\nSegera lakukan pembersihan atau ganti air.';

    await _showNotification(
      id: 3,
      title: title,
      body: body,
      payload: 'turbidity_warning',
    );

    _updateLastNotificationTime(notificationId);
  }

  Future<void> showFoodLevelAlert({
    required int percentage,
  }) async {
    print('✅ Food level notification sent - NO COOLDOWN');

    final String title = percentage < 10
        ? '🔴 Pakan Hampir Habis!'
        : '⚠️ Stok Pakan Menipis!';
    final String body = percentage < 10
        ? 'Stok pakan tersisa $percentage%. Segera isi ulang wadah pakan!'
        : 'Stok pakan tersisa $percentage%. Siapkan pakan cadangan.';

    await _showNotification(
      id: 4,
      title: title,
      body: body,
      payload: 'food_level_warning',
    );
  }

  Future<void> showStokCairanAlert({
    required String cairanType,
    required int percentage,
  }) async {
    final String notificationId = cairanType == 'ASAM'
        ? 'stok_asam_notification'
        : 'stok_basa_notification';

    if (!_canSendNotification(notificationId, _phCooldown)) {
      print('⏱️ Stok $cairanType notification skipped - cooldown active');
      return;
    }

    String title;
    String body;

    if (percentage <= 10) {
      // Kritis
      title = cairanType == 'ASAM'
          ? '🔴 Cairan Asam Hampir Habis!'
          : '🔴 Cairan Basa Hampir Habis!';
      body = cairanType == 'ASAM'
          ? 'Stok cairan asam tersisa $percentage%. KRITIS! Segera isi ulang sebelum sistem tidak bisa mengontrol pH.'
          : 'Stok cairan basa tersisa $percentage%. KRITIS! Segera isi ulang sebelum sistem tidak bisa mengontrol pH.';
    } else if (percentage <= 30) {
      // Rendah
      title = cairanType == 'ASAM'
          ? '⚠️ Cairan Asam Rendah!'
          : '⚠️ Cairan Basa Rendah!';
      body = cairanType == 'ASAM'
          ? 'Stok cairan asam tersisa $percentage%. Segera siapkan cairan pengganti.'
          : 'Stok cairan basa tersisa $percentage%. Segera siapkan cairan pengganti.';
    } else {
      // Menipis (31-50%)
      title = cairanType == 'ASAM'
          ? '🟡 Cairan Asam Menipis'
          : '🟡 Cairan Basa Menipis';
      body = cairanType == 'ASAM'
          ? 'Stok cairan asam tersisa $percentage%. Periksa ketersediaan cairan.'
          : 'Stok cairan basa tersisa $percentage%. Periksa ketersediaan cairan.';
    }

    await _showNotification(
      id: cairanType == 'ASAM' ? 7 : 8,
      title: title,
      body: body,
      payload: 'stok_cairan_${cairanType.toLowerCase()}_warning',
    );

    _updateLastNotificationTime(notificationId);
    print('✅ Stok $cairanType notification sent');
  }

  Future<void> showRelayAlert({
    required String relayType, // "ASAM" atau "BASA"
    required double phValue,
  }) async {

    final String notificationId = relayType == 'ASAM'
        ? 'relay_asam_notification'
        : 'relay_basa_notification';

    if (!_canSendNotification(notificationId, _relayCooldown)) {
      print('⏱️ Relay $relayType notification skipped - cooldown active');
      return;
    }

    final String title = relayType == 'ASAM'
        ? '🔴 Relay Asam Aktif!'
        : '🔵 Relay Basa Aktif!';

    final String body = relayType == 'ASAM'
        ? 'Sistem otomatis menambahkan larutan asam ke kolam.\npH saat ini: ${phValue.toStringAsFixed(2)}\nTarget: menurunkan pH ke range normal.'
        : 'Sistem otomatis menambahkan larutan basa ke kolam.\npH saat ini: ${phValue.toStringAsFixed(2)}\nTarget: menaikkan pH ke range normal.';

    await _showNotification(
      id: relayType == 'ASAM' ? 5 : 6, // ID berbeda untuk asam dan basa
      title: title,
      body: body,
      payload: 'relay_${relayType.toLowerCase()}_triggered',
    );

    _updateLastNotificationTime(notificationId);
    print('✅ Relay $relayType notification sent');
  }

  Future<void> showPumpDosingAlert({
    required String pumpType, // "ASAM" atau "BASA"
    required double phValue,
    required int durationSeconds, // Durasi pompa menyala (opsional)
  }) async {
    final String notificationId = pumpType == 'ASAM'
        ? 'pump_asam_notification'
        : 'pump_basa_notification';

    if (!_canSendNotification(notificationId, _pumpDosingCooldown)) {
      print('⏱️ Pump Dosing $pumpType notification skipped - cooldown active');
      return;
    }

    final String emoji = pumpType == 'ASAM' ? '🔻' : '🔺';
    final String title = pumpType == 'ASAM'
        ? '$emoji Pompa Asam Menyala!'
        : '$emoji Pompa Basa Menyala!';

    final String action = pumpType == 'ASAM'
        ? 'menurunkan pH'
        : 'menaikkan pH';

    final String body = 'Pompa dosing ${pumpType.toLowerCase()} sedang bekerja untuk $action.\n'
        'pH saat ini: ${phValue.toStringAsFixed(2)}\n'
        'Durasi: ${durationSeconds}s\n'
        'Sistem akan otomatis menyesuaikan pH ke range normal (6.5-8.5).';

    await _showNotification(
      id: pumpType == 'ASAM' ? 9 : 10, // ID berbeda untuk pompa asam dan basa
      title: title,
      body: body,
      payload: 'pump_dosing_${pumpType.toLowerCase()}_active',
    );

    _updateLastNotificationTime(notificationId);
    print('✅ Pump Dosing $pumpType notification sent');
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'aqualis_channel',
      'Aqualis Notifications',
      channelDescription: 'Notifikasi peringatan untuk kualitas air kolam',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}