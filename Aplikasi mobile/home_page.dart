import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:firebase_database/firebase_database.dart';
import 'notification_service.dart';
import 'ph_control_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}
StreamSubscription? _phControlLogListener;
String? _lastProcessedLogKey;

class _HomePageState extends State<HomePage> {
  // Firebase Database Reference
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Notification Service
  final NotificationService _notificationService = NotificationService();

  // StreamSubscriptions untuk cancel listeners
  StreamSubscription? _tempListener;
  StreamSubscription? _turbidityListener;
  StreamSubscription? _phListener;
  StreamSubscription? _stokAsamListener;
  StreamSubscription? _stokBasaListener;
  StreamSubscription? _acidPumpListener;
  StreamSubscription? _basePumpListener;

  // Data sensor
  double phValue = 7.0;
  double tempValue = 0.0;
  double turbidityValue = 0.0;

  // Status
  String tempStatus = "Memuat...";
  String turbidityStatus = "Memuat...";
  String phStatus = "Memuat...";
  bool tempWarning = false;
  bool turbidityWarning = false;
  bool phWarning = false;

  // Previous warning states untuk deteksi perubahan
  bool _previousTempWarning = false;
  bool _previousTurbidityWarning = false;
  bool _previousPhWarning = false;

  // Stok Cairan Asam dan Basa
  int stokAsamPercentage = 0;
  String stokAsamStatus = "Memuat...";
  bool stokAsamWarning = false;
  bool _previousStokAsamWarning = false;

  int stokBasaPercentage = 0;
  String stokBasaStatus = "Memuat...";
  bool stokBasaWarning = false;
  bool _previousStokBasaWarning = false;
  bool acidPumpStatus = false;
  bool basePumpStatus = false;

  // Previous pump states untuk deteksi perubahan (menyala dari mati)
  bool _previousAcidPumpStatus = false;
  bool _previousBasePumpStatus = false;

  // Valve control
  bool isValveOpen = false;
  bool isLoading = false;

  // Connection status
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _setupFirebaseListeners();
    _setupPhControlLogListener();
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();
  }

  void _setupFirebaseListeners() {
    const String deviceId = 'ESP32_N3FARM_001';

    // Listener untuk Temperature
    _tempListener = _database.child('$deviceId/sensors/temperature').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          tempValue = (data['value'] ?? 0.0).toDouble();
          tempStatus = data['status'] ?? 'Unknown';
          tempWarning = data['warning'] ?? false;
          isConnected = true;
        });

        // 🔔 Cek dan kirim notifikasi temperature
        _checkTemperatureWarning();
      }
    }, onError: (error) {
      print('Error temperature: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    // Listener untuk Turbidity
    _turbidityListener = _database.child('$deviceId/sensors/turbidity').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          turbidityValue = (data['ntu'] ?? 0.0).toDouble();
          turbidityStatus = data['status'] ?? 'Unknown';
          turbidityWarning = data['warning'] ?? false;
          isConnected = true;
        });

        // 🔔 Cek dan kirim notifikasi turbidity
        _checkTurbidityWarning();
      }
    }, onError: (error) {
      print('Error turbidity: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    // Listener untuk pH
    _phListener = _database.child('$deviceId/sensors/ph').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          phValue = (data['value'] ?? 7.0).toDouble();
          phStatus = data['status'] ?? 'Unknown';
          phWarning = data['warning'] ?? false;
          isConnected = true;
        });

        // 🔔 Cek dan kirim notifikasi pH
        _checkPhWarning();
      }
    }, onError: (error) {
      print('Error pH: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    // Listener untuk Stok Cairan Asam
    _stokAsamListener = _database.child('$deviceId/sensors/stokCairan/asam').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          stokAsamPercentage = (data['percentage'] ?? 0);
          stokAsamStatus = data['status'] ?? 'Unknown';
          stokAsamWarning = data['warning'] ?? false;
          isConnected = true;
        });

        // 🔔 Cek dan kirim notifikasi stok asam
        _checkStokAsamWarning();
      }
    }, onError: (error) {
      print('Error stok asam: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    // Listener untuk Stok Cairan Basa
    _stokBasaListener = _database.child('$deviceId/sensors/stokCairan/basa').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          stokBasaPercentage = (data['percentage'] ?? 0);
          stokBasaStatus = data['status'] ?? 'Unknown';
          stokBasaWarning = data['warning'] ?? false;
          isConnected = true;
        });

        // 🔔 Cek dan kirim notifikasi stok basa
        _checkStokBasaWarning();
      }
    }, onError: (error) {
      print('Error stok basa: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    // Listener untuk Status Pompa Asam
    _acidPumpListener = _database.child('$deviceId/dosingPump/acidPump/status').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.value != null) {
        final bool newStatus = event.snapshot.value as bool? ?? false;

        // Deteksi perubahan dari mati ke menyala
        if (newStatus && !_previousAcidPumpStatus) {
          // Pompa baru menyala, kirim notifikasi
          _notificationService.showPumpDosingAlert(
            pumpType: 'ASAM',
            phValue: phValue,
            durationSeconds: 10, // Sesuaikan dengan durasi aktual dari Firebase jika tersedia
          );
        }

        setState(() {
          acidPumpStatus = newStatus;
          _previousAcidPumpStatus = newStatus;
        });
      }
    });

    // Listener untuk Status Pompa Basa
    _basePumpListener = _database.child('$deviceId/dosingPump/basePump/status').onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.value != null) {
        final bool newStatus = event.snapshot.value as bool? ?? false;

        // Deteksi perubahan dari mati ke menyala
        if (newStatus && !_previousBasePumpStatus) {
          // Pompa baru menyala, kirim notifikasi
          _notificationService.showPumpDosingAlert(
            pumpType: 'BASA',
            phValue: phValue,
            durationSeconds: 10, // Sesuaikan dengan durasi aktual dari Firebase jika tersedia
          );
        }

        setState(() {
          basePumpStatus = newStatus;
          _previousBasePumpStatus = newStatus;
        });
      }
    });
  }

  void _setupPhControlLogListener() {
    const String deviceId = 'ESP32_N3FARM_001';

    _phControlLogListener = _database
        .child('$deviceId/phControlLog')
        .orderByKey()
        .limitToLast(1) // Ambil log terbaru
        .onChildAdded
        .listen((event) {
      if (!mounted) return;

      final logKey = event.snapshot.key;

      // Skip jika log sudah diproses
      if (logKey == _lastProcessedLogKey) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;

        final String type = data['type'] ?? '';
        final double phBefore = (data['phBefore'] ?? 7.0).toDouble();

        // Trigger notifikasi
        if (type == 'ASAM') {
          _notificationService.showRelayAlert(
            relayType: 'ASAM',
            phValue: phBefore,
          );
        } else if (type == 'BASA') {
          _notificationService.showRelayAlert(
            relayType: 'BASA',
            phValue: phBefore,
          );
        }

        _lastProcessedLogKey = logKey;
        print('Relay $type detected');
      }
    });
  }

  // 🔔 Fungsi untuk cek pH warning
  void _checkPhWarning() {
    // Hanya kirim notifikasi jika warning berubah dari false ke true
    if (phWarning && !_previousPhWarning) {
      if (phValue > 8.0) {
        _notificationService.showPhAlert(
          phValue: phValue,
          isHigh: true,
        );
      } else if (phValue < 7.0) {
        _notificationService.showPhAlert(
          phValue: phValue,
          isHigh: false,
        );
      }
    }
    _previousPhWarning = phWarning;
  }

  // 🔔 Fungsi untuk cek temperature warning
  void _checkTemperatureWarning() {
    // Hanya kirim notifikasi jika warning berubah dari false ke true
    if (tempWarning && !_previousTempWarning) {
      if (tempValue > 30.0) {
        _notificationService.showTemperatureAlert(
          tempValue: tempValue,
          isHigh: true,
        );
      } else if (tempValue < 25.0) {
        _notificationService.showTemperatureAlert(
          tempValue: tempValue,
          isHigh: false,
        );
      }
    }
    _previousTempWarning = tempWarning;
  }

  // 🔔 Fungsi untuk cek turbidity warning
  void _checkTurbidityWarning() {
    // Hanya kirim notifikasi jika warning berubah dari false ke true
    if (turbidityWarning && !_previousTurbidityWarning) {
      if (turbidityValue > 50.0) {
        _notificationService.showTurbidityAlert(
          ntuValue: turbidityValue,
        );
      }
    }
    _previousTurbidityWarning = turbidityWarning;
  }

  // 🔔 Fungsi untuk cek stok asam warning
  void _checkStokAsamWarning() {
    // Hanya kirim notifikasi jika warning berubah dari false ke true
    if (stokAsamWarning && !_previousStokAsamWarning) {
      _notificationService.showStokCairanAlert(
        cairanType: 'ASAM',
        percentage: stokAsamPercentage,
      );
    }
    _previousStokAsamWarning = stokAsamWarning;
  }

  // 🔔 Fungsi untuk cek stok basa warning
  void _checkStokBasaWarning() {
    // Hanya kirim notifikasi jika warning berubah dari false ke true
    if (stokBasaWarning && !_previousStokBasaWarning) {
      _notificationService.showStokCairanAlert(
        cairanType: 'BASA',
        percentage: stokBasaPercentage,
      );
    }
    _previousStokBasaWarning = stokBasaWarning;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            // Logo Aqualis
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/Aqualis_Logo_with_Nila_Fish.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Home',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 24,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isConnected ? Colors.green[100] : Colors.red[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isConnected ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? Colors.green[900] : Colors.red[900],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildGaugeIndicator(
                              label: 'pH',
                              value: phValue,
                              minValue: 0,
                              maxValue: 14,
                              unit: '',
                              status: phStatus,
                              hasWarning: phWarning,
                            ),
                            _buildGaugeIndicator(
                              label: 'Suhu',
                              value: tempValue,
                              minValue: 0,
                              maxValue: 50,
                              unit: '°C',
                              status: tempStatus,
                              hasWarning: tempWarning,
                            ),
                            _buildGaugeIndicator(
                              label: 'Turbidity',
                              value: turbidityValue,
                              minValue: 0,
                              maxValue: 100,
                              unit: 'NTU',
                              status: turbidityStatus,
                              hasWarning: turbidityWarning,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PhControlHistoryPage(),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Riwayat Kontrol pH',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey[700],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [Colors.blue[50]!, Colors.blue[100]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[700],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.opacity,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Kontrol pH Otomatis',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pompa Dosing',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: acidPumpStatus ? Colors.green : Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Asam: ${acidPumpStatus ? "Menyala" : "Mati"}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: acidPumpStatus ? Colors.green[700] : Colors.red[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: basePumpStatus ? Colors.green : Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Basa: ${basePumpStatus ? "Menyala" : "Mati"}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: basePumpStatus ? Colors.green[700] : Colors.red[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isLoading ? null : _toggleValve,
                              icon: isLoading
                                  ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                                  : Icon(
                                isValveOpen
                                    ? Icons.lock_open
                                    : Icons.lock,
                              ),
                              label: Text(
                                isLoading
                                    ? 'Memproses...'
                                    : (isValveOpen ? 'Mati' : 'Aktif'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isValveOpen
                                    ? Colors.orange[700]
                                    : Colors.blue[700],
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue[200]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.blue[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pompa akan terbuka otomatis jika pH < 7.0 atau > 8.0',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Card untuk Stok Cairan Asam dan Basa
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [Colors.purple[50]!, Colors.purple[100]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.purple[700],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.science,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Stok Cairan pH',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStokCairanGauge(
                              label: 'Cairan Asam',
                              percentage: stokAsamPercentage,
                              status: stokAsamStatus,
                              hasWarning: stokAsamWarning,
                              color: Colors.red,
                              icon: Icons.remove_circle,
                            ),
                            _buildStokCairanGauge(
                              label: 'Cairan Basa',
                              percentage: stokBasaPercentage,
                              status: stokBasaStatus,
                              hasWarning: stokBasaWarning,
                              color: Colors.blue,
                              icon: Icons.add_circle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.purple[200]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.purple[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sistem akan memberi notifikasi jika stok cairan menipis atau kritis',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.purple[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Colors.amber[700],
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Tips: Periksa kualitas air secara berkala untuk menjaga kesehatan ikan',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGaugeIndicator({
    required String label,
    required double value,
    required double minValue,
    required double maxValue,
    required String unit,
    required String status,
    required bool hasWarning,
    bool isStatic = false,
  }) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: minValue,
                    maximum: maxValue,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: AxisLineStyle(
                      thickness: 0.15,
                      cornerStyle: CornerStyle.bothCurve,
                      color: Colors.grey[300],
                      thicknessUnit: GaugeSizeUnit.factor,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: value,
                        cornerStyle: CornerStyle.bothCurve,
                        width: 0.15,
                        sizeUnit: GaugeSizeUnit.factor,
                        enableAnimation: true,
                        animationDuration: 1200,
                        animationType: AnimationType.ease,
                        gradient: SweepGradient(
                          colors: _getGradientColors(label, hasWarning),
                          stops: const <double>[0.0, 0.5, 1.0],
                        ),
                      ),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        angle: 90,
                        positionFactor: 0.5,
                        widget: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              value.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            if (unit.isNotEmpty)
                              Text(
                                unit,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (hasWarning && !isStatic)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.warning,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            if (isStatic)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Static',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        if (status.isNotEmpty && !isStatic)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hasWarning ? Colors.red[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasWarning ? Colors.red[200]! : Colors.green[200]!,
                width: 1,
              ),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: hasWarning ? Colors.red[700] : Colors.green[700],
              ),
            ),
          ),
      ],
    );
  }

  List<Color> _getGradientColors(String label, bool hasWarning) {
    if (hasWarning) {
      return const [
        Color(0xFFEF5350),
        Color(0xFFE53935),
        Color(0xFFD32F2F),
      ];
    }

    switch (label) {
      case 'pH':
        return const [
          Color(0xFF4FC3F7),
          Color(0xFF2196F3),
          Color(0xFF1976D2),
        ];
      case 'Suhu':
        return const [
          Color(0xFFFF9800),
          Color(0xFFF57C00),
          Color(0xFFE65100),
        ];
      case 'Turbidity':
        return const [
          Color(0xFF66BB6A),
          Color(0xFF4CAF50),
          Color(0xFF388E3C),
        ];
      default:
        return const [
          Color(0xFF9E9E9E),
          Color(0xFF757575),
          Color(0xFF616161),
        ];
    }
  }

  // Widget untuk gauge stok cairan
  Widget _buildStokCairanGauge({
    required String label,
    required int percentage,
    required String status,
    required bool hasWarning,
    required Color color,
    required IconData icon,
  }) {
    // Tentukan warna berdasarkan percentage
    Color gaugeColor;
    if (hasWarning) {
      if (percentage <= 10) {
        gaugeColor = Colors.red; // Kritis
      } else if (percentage <= 30) {
        gaugeColor = Colors.orange; // Rendah
      } else {
        gaugeColor = Colors.yellow; // Menipis
      }
    } else {
      gaugeColor = color; // Normal (merah untuk asam, biru untuk basa)
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: 0,
                    maximum: 100,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: AxisLineStyle(
                      thickness: 0.15,
                      cornerStyle: CornerStyle.bothCurve,
                      color: Colors.grey[300],
                      thicknessUnit: GaugeSizeUnit.factor,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: percentage.toDouble(),
                        cornerStyle: CornerStyle.bothCurve,
                        width: 0.15,
                        sizeUnit: GaugeSizeUnit.factor,
                        enableAnimation: true,
                        animationDuration: 1200,
                        animationType: AnimationType.ease,
                        gradient: SweepGradient(
                          colors: hasWarning
                              ? [
                            Colors.red[400]!,
                            Colors.orange[600]!,
                            Colors.red[700]!,
                          ]
                              : [
                            color.withOpacity(0.6),
                            color,
                            color.withOpacity(0.8),
                          ],
                          stops: const <double>[0.0, 0.5, 1.0],
                        ),
                      ),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        angle: 90,
                        positionFactor: 0.1,
                        widget: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 28,
                              color: hasWarning ? Colors.red[700] : color,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$percentage%',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: hasWarning ? Colors.red[700] : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (hasWarning)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.warning,
                  size: 14,
                  color: Colors.white,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: hasWarning ? Colors.red[50] : Colors.green[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasWarning ? Colors.red[200]! : Colors.green[200]!,
              width: 1,
            ),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: hasWarning ? Colors.red[700] : Colors.green[700],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleValve() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_rounded,
                color: Colors.orange[700],
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text('Konfirmasi'),
            ],
          ),
          content: Text(
            isValveOpen
                ? 'Apakah Anda yakin ingin mematikan pompa dosing?'
                : 'Apakah Anda yakin ingin menyalakan pompa dosing secara manual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isValveOpen
                    ? Colors.orange[700]
                    : Colors.red[700],
              ),
              child: const Text('Ya, Lanjutkan'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      isLoading = true;
    });

    try {
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        setState(() {
          isValveOpen = !isValveOpen;
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isValveOpen
                  ? '✓ Pompa berhasil dinyalakan'
                  : '✓ Pompa berhasil dimatikan',
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal mengontrol pompa: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Cancel semua Firebase listeners
    _tempListener?.cancel();
    _turbidityListener?.cancel();
    _phListener?.cancel();
    _stokAsamListener?.cancel();
    _stokBasaListener?.cancel();
    _phControlLogListener?.cancel();
    _acidPumpListener?.cancel();
    _basePumpListener?.cancel();
    super.dispose();
  }
}