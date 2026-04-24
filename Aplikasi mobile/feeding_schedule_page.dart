import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'feeding_form_page.dart';
import 'notification_service.dart';

class FeedingSchedulePage extends StatefulWidget {
  const FeedingSchedulePage({Key? key}) : super(key: key);

  @override
  State<FeedingSchedulePage> createState() => _FeedingSchedulePageState();
}

// Model untuk Feeding Schedule
class FeedingSchedule {
  final String id;
  final String time;
  final double weightGrams;
  final bool enabled;
  final String status;
  final bool isCompleted;

  FeedingSchedule({
    required this.id,
    required this.time,
    required this.weightGrams,
    required this.enabled,
    required this.status,
    required this.isCompleted,
  });

  FeedingSchedule copyWith({
    String? id,
    String? time,
    double? weightGrams,
    bool? enabled,
    String? status,
    bool? isCompleted,
  }) {
    return FeedingSchedule(
      id: id ?? this.id,
      time: time ?? this.time,
      weightGrams: weightGrams ?? this.weightGrams,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

// Model untuk Feeding Log
class FeedingLog {
  final String id;
  final String timestamp;
  final double weightGrams;
  final int durationMs;
  final DateTime dateTime;

  FeedingLog({
    required this.id,
    required this.timestamp,
    required this.weightGrams,
    required this.durationMs,
    required this.dateTime,
  });
}

class _FeedingSchedulePageState extends State<FeedingSchedulePage> {
  // Firebase Database Reference
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Notification Service
  final NotificationService _notificationService = NotificationService();

  // Device ID
  static const String deviceId = 'ESP32_N3FARM_001';

  // StreamSubscription untuk cancel listener
  StreamSubscription? _foodLevelListener;
  StreamSubscription? _schedulesListener;
  StreamSubscription? _feedingLogsListener;
  StreamSubscription? _samplingDataListener;  // 🆕 Listener untuk biomassa
  StreamSubscription? _adaptiveFeedingListener;  // 🆕 Listener untuk adaptive setting

  // Data jadwal pakan dari Firebase
  List<FeedingSchedule> schedules = [];
  bool isLoadingSchedules = true;

  // Data log pemberian pakan dari Firebase
  List<FeedingLog> feedingLogs = [];
  bool isLoadingLogs = true;

  // Data stok pakan dari Firebase
  int foodLevelPercentage = 0;
  String foodLevelStatus = "Memuat...";
  bool foodLevelWarning = false;
  bool isConnected = false;

  // 🆕 Data untuk Adaptive Feeding
  double latestBiomass = 0.0;  // kg
  double dailyFeedAmount = 0.0;  // gram (3% dari biomassa)
  bool isAdaptiveFeedingEnabled = false;
  bool isUpdatingSchedules = false;

  // Previous warning state untuk deteksi perubahan
  bool _previousFoodLevelWarning = false;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _setupFoodLevelListener();
    _setupSchedulesListener();
    _setupFeedingLogsListener();
    _setupSamplingDataListener();  // 🆕 Setup listener biomassa
    _setupAdaptiveFeedingListener();  // 🆕 Setup listener adaptive setting
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();
  }

  @override
  void dispose() {
    // Cancel Firebase listeners
    _foodLevelListener?.cancel();
    _schedulesListener?.cancel();
    _feedingLogsListener?.cancel();
    _samplingDataListener?.cancel();  // 🆕
    _adaptiveFeedingListener?.cancel();  // 🆕
    super.dispose();
  }

  void _setupFoodLevelListener() {
    // Listener untuk Food Level dari Firebase
    _foodLevelListener = _database
        .child('$deviceId/sensors/foodLevel')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        try {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            foodLevelPercentage = (data['percentage'] ?? 0).toInt();
            foodLevelStatus = data['status'] ?? 'Unknown';
            foodLevelWarning = data['warning'] ?? false;
            isConnected = true;
          });

          // 🔔 Cek dan kirim notifikasi food level
          _checkFoodLevelWarning();
        } catch (e) {
          print('Error parsing food level data: $e');
        }
      }
    }, onError: (error) {
      print('Error food level: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
          foodLevelStatus = 'Error';
        });
      }
    });
  }

  // 🔔 Fungsi untuk cek food level warning
  void _checkFoodLevelWarning() {
    // Hanya kirim notifikasi jika warning berubah dari false ke true
    if (foodLevelWarning && !_previousFoodLevelWarning) {
      _notificationService.showFoodLevelAlert(
        percentage: foodLevelPercentage,
      );
    }
    _previousFoodLevelWarning = foodLevelWarning;
  }

  void _setupSchedulesListener() {
    // Listener untuk Feeding Schedules dari Firebase
    _schedulesListener = _database
        .child('$deviceId/feeding/schedules')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        try {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final List<FeedingSchedule> loadedSchedules = [];

          data.forEach((key, value) {
            try {
              if (value is Map) {
                final hour = value['hour'] ?? 0;
                final minute = value['minute'] ?? 0;
                final weightGrams = (value['weight_grams'] ?? 0).toDouble();
                final enabled = value['enabled'] ?? false;

                // Format waktu
                final timeString =
                    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} WIB';

                // Cek apakah jadwal sudah lewat hari ini
                final now = DateTime.now();
                final scheduleTime = DateTime(now.year, now.month, now.day, hour, minute);
                final isPast = scheduleTime.isBefore(now);

                loadedSchedules.add(FeedingSchedule(
                  id: key.toString(),
                  time: timeString,
                  weightGrams: weightGrams,
                  enabled: enabled,
                  status: isPast ? 'Selesai' : 'Dijadwalkan',
                  isCompleted: isPast,
                ));
              }
            } catch (e) {
              print('Error parsing schedule $key: $e');
            }
          });

          // Sort berdasarkan waktu
          loadedSchedules.sort((a, b) {
            try {
              final timeA = a.time.split(' ')[0].split(':');
              final timeB = b.time.split(' ')[0].split(':');
              final hourA = int.parse(timeA[0]);
              final hourB = int.parse(timeB[0]);
              final minuteA = int.parse(timeA[1]);
              final minuteB = int.parse(timeB[1]);

              if (hourA != hourB) return hourA.compareTo(hourB);
              return minuteA.compareTo(minuteB);
            } catch (e) {
              print('Error sorting schedules: $e');
              return 0;
            }
          });

          if (mounted) {
            setState(() {
              schedules = loadedSchedules;
              isLoadingSchedules = false;
            });
          }
        } catch (e) {
          print('Error parsing schedules data: $e');
          if (mounted) {
            setState(() {
              schedules = [];
              isLoadingSchedules = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            schedules = [];
            isLoadingSchedules = false;
          });
        }
      }
    }, onError: (error) {
      print('Error schedules: $error');
      if (mounted) {
        setState(() {
          isLoadingSchedules = false;
        });
      }
    });
  }

  // Setup listener untuk feeding logs
  void _setupFeedingLogsListener() {
    _feedingLogsListener = _database
        .child('$deviceId/feedingLogs')
        .orderByKey()
        .limitToLast(10)  // Ambil 10 log terakhir
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        try {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final List<FeedingLog> loadedLogs = [];

          data.forEach((key, value) {
            try {
              if (value is Map) {
                final timestamp = value['timestamp'] ?? '';
                final weightGrams = (value['weightGrams'] ?? 0).toDouble();
                final durationMs = value['durationMs'] ?? 0;

                // Parse timestamp (format: "2026-01-17 18:05:03")
                DateTime dateTime;
                try {
                  dateTime = DateTime.parse(timestamp.replaceAll(' ', 'T'));
                } catch (e) {
                  dateTime = DateTime.now();
                }

                loadedLogs.add(FeedingLog(
                  id: key.toString(),
                  timestamp: timestamp,
                  weightGrams: weightGrams,
                  durationMs: durationMs,
                  dateTime: dateTime,
                ));
              }
            } catch (e) {
              print('Error parsing feeding log $key: $e');
            }
          });

          // Sort berdasarkan waktu (terbaru dulu)
          loadedLogs.sort((a, b) => b.dateTime.compareTo(a.dateTime));

          if (mounted) {
            setState(() {
              feedingLogs = loadedLogs;
              isLoadingLogs = false;
            });
          }
        } catch (e) {
          print('Error parsing feeding logs: $e');
          if (mounted) {
            setState(() {
              feedingLogs = [];
              isLoadingLogs = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            feedingLogs = [];
            isLoadingLogs = false;
          });
        }
      }
    }, onError: (error) {
      print('Error feeding logs: $error');
      if (mounted) {
        setState(() {
          isLoadingLogs = false;
        });
      }
    });
  }

  // 🆕 Setup listener untuk sampling data (biomassa)
  void _setupSamplingDataListener() {
    _samplingDataListener = _database
        .child('$deviceId/samplingData')
        .orderByChild('timestamp')
        .limitToLast(1)  // Ambil data terakhir saja
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        try {
          final data = event.snapshot.value as Map<dynamic, dynamic>;

          // Ambil entry terakhir
          if (data.isNotEmpty) {
            final lastEntry = data.values.last as Map<dynamic, dynamic>;
            final biomass = (lastEntry['total_biomass'] ?? 0.0).toDouble();

            if (mounted) {
              setState(() {
                latestBiomass = biomass;
                // Hitung 3% dari biomassa (dalam gram)
                dailyFeedAmount = (biomass * 1000 * 0.03);  // kg -> gram, kemudian 3%
              });

              // Jika adaptive feeding aktif, update schedules
              if (isAdaptiveFeedingEnabled && schedules.isNotEmpty) {
                _updateSchedulesWithAdaptiveWeight();
              }
            }
          }
        } catch (e) {
          print('Error parsing sampling data for adaptive feeding: $e');
        }
      }
    }, onError: (error) {
      print('Error sampling data listener: $error');
    });
  }

  // 🆕 Setup listener untuk adaptive feeding setting
  void _setupAdaptiveFeedingListener() {
    _adaptiveFeedingListener = _database
        .child('$deviceId/feeding/adaptiveEnabled')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final enabled = event.snapshot.value as bool? ?? false;
        if (mounted) {
          setState(() {
            isAdaptiveFeedingEnabled = enabled;
          });
        }
      }
    }, onError: (error) {
      print('Error adaptive feeding listener: $error');
    });
  }

  // 🆕 Update semua schedules dengan berat adaptif
  Future<void> _updateSchedulesWithAdaptiveWeight() async {
    if (schedules.isEmpty || dailyFeedAmount <= 0) return;
    if (isUpdatingSchedules) return;  // Prevent multiple updates

    setState(() {
      isUpdatingSchedules = true;
    });

    try {
      // Hitung berat per jadwal (bagi rata)
      final weightPerSchedule = dailyFeedAmount / schedules.length;

      // Update semua schedules
      for (final schedule in schedules) {
        // Hitung durasi servo
        final duration = _calculateServoDuration(weightPerSchedule);

        // Update di Firebase
        await _database
            .child('$deviceId/feeding/schedules/${schedule.id}')
            .update({
          'weight_grams': weightPerSchedule,
          'duration_ms': duration,
        });
      }

      if (mounted) {
        setState(() {
          isUpdatingSchedules = false;
        });
      }

      print('✓ Adaptive feeding: Updated all schedules to ${weightPerSchedule.toStringAsFixed(1)}g per feeding');
    } catch (e) {
      print('Error updating schedules: $e');
      if (mounted) {
        setState(() {
          isUpdatingSchedules = false;
        });
      }
    }
  }

  // 🆕 Toggle adaptive feeding
  Future<void> _toggleAdaptiveFeeding() async {
    try {
      final newValue = !isAdaptiveFeedingEnabled;

      // Update di Firebase
      await _database
          .child('$deviceId/feeding/adaptiveEnabled')
          .set(newValue);

      // Jika diaktifkan dan ada biomassa, langsung update schedules
      if (newValue && latestBiomass > 0 && schedules.isNotEmpty) {
        await _updateSchedulesWithAdaptiveWeight();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✓ Pakan Adaptif Aktif\n'
                    'Biomassa: ${latestBiomass.toStringAsFixed(1)} kg\n'
                    'Total pakan/hari: ${dailyFeedAmount.toStringAsFixed(1)}g (3%)\n'
                    'Per jadwal: ${(dailyFeedAmount / schedules.length).toStringAsFixed(1)}g',
              ),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (!newValue && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pakan Adaptif Dinonaktifkan'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error toggling adaptive feeding: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              ' Pakan Ikan',
              style: TextStyle(color: Colors.black87),
            ),
            const SizedBox(width: 12),
            // Connection indicator
            if (isConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Online',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddSchedule,
        backgroundColor: Colors.blue[600],
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh akan otomatis melalui listeners
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Stok Pakan
              _buildFoodStockCard(),

              const SizedBox(height: 16),

              // 🆕 Card Pakan Adaptif
              _buildAdaptiveFeedingCard(),

              const SizedBox(height: 16),

              // Card Jadwal Pakan Hari Ini
              _buildSchedulesCard(),

              const SizedBox(height: 16),

              // Card Log Pemberian Pakan
              _buildFeedingLogsCard(),

              const SizedBox(height: 16),

              // Info Card
              _buildInfoCard(),

              const SizedBox(height: 80), // Padding untuk FAB
            ],
          ),
        ),
      ),
    );
  }

  // 🆕 Card untuk Pakan Adaptif
  Widget _buildAdaptiveFeedingCard() {
    final weightPerSchedule = schedules.isNotEmpty
        ? dailyFeedAmount / schedules.length
        : 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              isAdaptiveFeedingEnabled
                  ? Colors.green[50]!
                  : Colors.grey[100]!,
              Colors.white,
            ],
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
                    color: isAdaptiveFeedingEnabled
                        ? Colors.green[100]
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: isAdaptiveFeedingEnabled
                        ? Colors.green[700]
                        : Colors.grey[600],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pakan Adaptif (3% Biomassa)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Switch(
                  value: isAdaptiveFeedingEnabled,
                  onChanged: isUpdatingSchedules ? null : (value) {
                    _toggleAdaptiveFeeding();
                  },
                  activeColor: Colors.green[700],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info biomassa dan perhitungan
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isAdaptiveFeedingEnabled
                    ? Colors.green[50]
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isAdaptiveFeedingEnabled
                      ? Colors.green[200]!
                      : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Biomassa Terakhir:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        '${latestBiomass.toStringAsFixed(1)} kg',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: latestBiomass > 0
                              ? Colors.black87
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Pakan/Hari (3%):',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        '${dailyFeedAmount.toStringAsFixed(1)} gram',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isAdaptiveFeedingEnabled
                              ? Colors.green[700]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  if (schedules.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Per Jadwal (${schedules.length}x):',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        Text(
                          '${weightPerSchedule.toStringAsFixed(1)} gram',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isAdaptiveFeedingEnabled
                                ? Colors.green[700]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Status dan info
            if (latestBiomass <= 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange[200]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: Colors.orange[700],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Belum ada data sampling. Lakukan sampling untuk mengaktifkan pakan adaptif.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (isAdaptiveFeedingEnabled && isUpdatingSchedules)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blue[700]!,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Memperbarui jadwal pakan...',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (isAdaptiveFeedingEnabled)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green[200]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green[700],
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pakan adaptif aktif. Berat pakan akan otomatis disesuaikan dengan biomassa terbaru.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.grey[600],
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Aktifkan untuk menyesuaikan berat pakan otomatis berdasarkan biomassa.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Jadwal Pakan Hari Ini',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (schedules.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${schedules.where((s) => s.isCompleted).length}/${schedules.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoadingSchedules)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (schedules.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Belum ada jadwal pakan',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap tombol + untuk menambah jadwal',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: schedules.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final schedule = schedules[index];
                  return _buildScheduleItem(schedule);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleItem(FeedingSchedule schedule) {
    final bool isActive = !schedule.isCompleted && schedule.enabled;

    return InkWell(
      onTap: isAdaptiveFeedingEnabled
          ? null  // Disable edit saat adaptive aktif
          : () => _navigateToEditSchedule(schedule),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.blue[200]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icon waktu
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive ? Colors.blue[600] : Colors.grey[400],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                schedule.isCompleted ? Icons.check_circle : Icons.access_time,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Info jadwal
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.time,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${schedule.weightGrams.toStringAsFixed(0)} gram',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? Colors.green : Colors.grey[300],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isActive ? 'Aktif' : schedule.status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : Colors.grey[700],
                ),
              ),
            ),
            if (!isAdaptiveFeedingEnabled) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Widget untuk card feeding logs
  Widget _buildFeedingLogsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: Colors.purple[700],
                ),
                const SizedBox(width: 8),
                const Text(
                  'Riwayat Pemberian Pakan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isLoadingLogs)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (feedingLogs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Belum ada riwayat pemberian pakan',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: feedingLogs.length > 5 ? 5 : feedingLogs.length,
                separatorBuilder: (context, index) => Divider(
                  height: 16,
                  color: Colors.grey[300],
                ),
                itemBuilder: (context, index) {
                  final log = feedingLogs[index];
                  return _buildFeedingLogItem(log);
                },
              ),
            if (feedingLogs.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      _showAllLogsDialog();
                    },
                    child: Text(
                      'Lihat Semua (${feedingLogs.length})',
                      style: TextStyle(
                        color: Colors.purple[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedingLogItem(FeedingLog log) {
    final String formattedTime = DateFormat('HH:mm').format(log.dateTime);
    final String formattedDate = DateFormat('dd MMM yyyy').format(log.dateTime);
    final bool isToday = _isToday(log.dateTime);

    return Row(
      children: [
        // Icon
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.restaurant,
            color: Colors.purple[700],
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${log.weightGrams.toStringAsFixed(0)} gram',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Durasi: ${(log.durationMs / 1000).toStringAsFixed(1)}s',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        // Waktu
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isToday ? 'Hari ini' : formattedDate,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  void _showAllLogsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: Colors.purple[700],
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Semua Riwayat Pemberian Pakan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // List
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: feedingLogs.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 16,
                      color: Colors.grey[300],
                    ),
                    itemBuilder: (context, index) {
                      final log = feedingLogs[index];
                      return _buildFeedingLogItem(log);
                    },
                  ),
                ),
                // Close button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[700],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Tutup',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFoodStockCard() {
    // Tentukan warna berdasarkan percentage
    Color stockColor;
    IconData stockIcon;

    if (foodLevelPercentage < 10) {
      stockColor = Colors.red;
      stockIcon = Icons.error;
    } else if (foodLevelPercentage < 30) {
      stockColor = Colors.orange;
      stockIcon = Icons.warning;
    } else {
      stockColor = Colors.green;
      stockIcon = Icons.check_circle;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              stockColor.withOpacity(0.1),
              Colors.white,
            ],
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
                    color: stockColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: stockColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Stok Pakan',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  stockIcon,
                  color: stockColor,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$foodLevelPercentage%',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: stockColor,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: stockColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      foodLevelStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: stockColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Warning message jika stok rendah
            if (foodLevelWarning)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: stockColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: stockColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: stockColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        foodLevelPercentage < 10
                            ? 'Stok pakan hampir habis! Segera isi ulang.'
                            : 'Stok pakan mulai menipis.',
                        style: TextStyle(
                          fontSize: 12,
                          color: stockColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (!foodLevelWarning) const SizedBox(height: 12),

            if (!foodLevelWarning)
              Text(
                'Stok pakan akan terisi otomatis saat Anda mengisi wadah pakan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
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
            Expanded(
              child: Text(
                'Tips: Beri pakan ikan secara teratur 2-3 kali sehari untuk pertumbuhan optimal',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAddSchedule() async {
    // Cek apakah adaptive feeding aktif
    if (isAdaptiveFeedingEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Nonaktifkan pakan adaptif untuk menambah jadwal manual'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Cek apakah sudah ada 3 jadwal
    if (schedules.length >= 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Maksimal 3 jadwal pakan per hari'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeedingFormPage(isEdit: false),
      ),
    );

    if (result != null && result is FeedingSchedule) {
      _saveScheduleToFirebase(result);
    }
  }

  void _navigateToEditSchedule(FeedingSchedule schedule) async {
    // Cek apakah adaptive feeding aktif
    if (isAdaptiveFeedingEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Nonaktifkan pakan adaptif untuk mengedit jadwal'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeedingFormPage(
          isEdit: true,
          schedule: schedule,
        ),
      ),
    );

    if (result != null) {
      if (result == 'delete') {
        _deleteScheduleFromFirebase(schedule.id);
      } else if (result is FeedingSchedule) {
        _updateScheduleInFirebase(schedule.id, result);
      }
    }
  }

  Future<void> _saveScheduleToFirebase(FeedingSchedule schedule) async {
    try {
      // Parse time
      final timeParts = schedule.time.split(' ')[0].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // Hitung durasi servo berdasarkan berat
      final duration = _calculateServoDuration(schedule.weightGrams);

      // Generate schedule key (schedule_0, schedule_1, schedule_2)
      final scheduleKey = 'schedule_${schedules.length}';

      // Save to Firebase
      await _database.child('$deviceId/feeding/schedules/$scheduleKey').set({
        'hour': hour,
        'minute': minute,
        'weight_grams': schedule.weightGrams,
        'duration_ms': duration,
        'enabled': true,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Jadwal berhasil ditambahkan'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error saving schedule: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✗ Gagal menambahkan jadwal: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _updateScheduleInFirebase(
      String scheduleKey, FeedingSchedule schedule) async {
    try {
      // Parse time
      final timeParts = schedule.time.split(' ')[0].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // Hitung durasi servo berdasarkan berat
      final duration = _calculateServoDuration(schedule.weightGrams);

      // Update to Firebase
      await _database.child('$deviceId/feeding/schedules/$scheduleKey').update({
        'hour': hour,
        'minute': minute,
        'weight_grams': schedule.weightGrams,
        'duration_ms': duration,
        'enabled': schedule.enabled,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Jadwal berhasil diperbarui'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error updating schedule: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✗ Gagal memperbarui jadwal: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteScheduleFromFirebase(String scheduleKey) async {
    try {
      await _database.child('$deviceId/feeding/schedules/$scheduleKey').remove();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Jadwal berhasil dihapus'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error deleting schedule: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✗ Gagal menghapus jadwal: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Fungsi untuk menghitung durasi servo berdasarkan berat
  int _calculateServoDuration(double weightGrams) {
    if (weightGrams <= 0) {
      return 0;
    }
    // Segmen 1: 0g - 35.4g (0ms - 250ms)
    if (weightGrams <= 35.4) {
      return (weightGrams * 250 / 35.4).round();
    }
    // Segmen 2: 35.4g - 63.0g (250ms - 500ms)
    if (weightGrams <= 63.0) {
      double ratio = (weightGrams - 35.4) / (63.0 - 35.4);
      return (250 + ratio * 250).round();
    }
    // Segmen 3: 63.0g - 95.6g (500ms - 750ms)
    if (weightGrams <= 95.6) {
      double ratio = (weightGrams - 63.0) / (95.6 - 63.0);
      return (500 + ratio * 250).round();
    }
    // Segmen 4: 95.6g - 121.8g (750ms - 1000ms)
    if (weightGrams <= 121.8) {
      double ratio = (weightGrams - 95.6) / (121.8 - 95.6);
      return (750 + ratio * 250).round();
    }
    // Di atas 121.8g: ekstrapolasi linear
    double ratio = (weightGrams - 121.8) / (121.8 - 95.6);
    return (1000 + ratio * 250).round();
  }
}