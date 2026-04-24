import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'sampling_input_page.dart';
import 'growth_metrics_page.dart';

class SamplingHistoryPage extends StatefulWidget {
  const SamplingHistoryPage({Key? key}) : super(key: key);

  @override
  State<SamplingHistoryPage> createState() => _SamplingHistoryPageState();
}

class _SamplingHistoryPageState extends State<SamplingHistoryPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // StreamSubscriptions untuk cancel listeners
  StreamSubscription? _initialStockListener;
  StreamSubscription? _samplingDataListener;

  // Data riwayat penimbangan dari Firebase
  List<SamplingData> samplingHistory = [];

  // Data tebar awal dari Firebase
  int initialStockCount = 0;

  // Loading state
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupFirebaseListeners();
  }

  void _setupFirebaseListeners() {
    const String deviceId = 'ESP32_N3FARM_001';

    // Listener untuk Initial Stock
    _initialStockListener = _database
        .child('$deviceId/farmData/initialStock')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        setState(() {
          initialStockCount = (event.snapshot.value as num).toInt();
          isLoading = false;
        });
      } else {
        // Jika belum ada data, set default 1000
        setState(() {
          initialStockCount = 0;
          isLoading = false;
        });
      }
    }, onError: (error) {
      print('Error loading initial stock: $error');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });

    // Listener untuk Sampling Data
    _samplingDataListener = _database
        .child('$deviceId/samplingData')
        .orderByChild('timestamp')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;

        List<SamplingData> tempList = [];
        data.forEach((key, value) {
          try {
            final samplingData = SamplingData.fromFirebase(
              key.toString(),
              value as Map<dynamic, dynamic>,
            );
            tempList.add(samplingData);
          } catch (e) {
            print('Error parsing sampling data: $e');
          }
        });

        // Sort by date descending (terbaru di atas)
        tempList.sort((a, b) => b.date.compareTo(a.date));

        setState(() {
          samplingHistory = tempList;
        });
      } else {
        setState(() {
          samplingHistory = [];
        });
      }
    }, onError: (error) {
      print('Error loading sampling data: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Penimbangan Ikan (Sampling)',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),

        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GrowthMetricsPage()),
              );
            },
            tooltip: 'Lihat Metrik Pertumbuhan',
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () {
              _navigateToInputPage();
            },
            tooltip: 'Tambah Data Sampling',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Colors.blue[700],
        ),
      )
          : RefreshIndicator(
        onRefresh: () async {
          // Refresh data dari Firebase
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
                _buildSummaryCard(),
                const SizedBox(height: 20),
                _buildSectionHeader('Riwayat Penimbangan Ikan'),
                const SizedBox(height: 12),
                if (samplingHistory.isEmpty)
                  _buildEmptyState()
                else
                  ...samplingHistory.map((data) => _buildHistoryCard(data)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final latestData = samplingHistory.isNotEmpty ? samplingHistory.first : null;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue[600]!,
              Colors.blue[800]!,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pie_chart_outline,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ringkasan Data Terkini',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Tebar Awal',
                    initialStockCount.toString(),
                    'ekor',
                    Icons.water_drop,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryItem(
                    'Jumlah Saat Ini',
                    latestData != null
                        ? (initialStockCount * latestData.survivalRate / 100)
                        .toInt()
                        .toString()
                        : '-',
                    'ekor',
                    Icons.pets,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'SR Terkini',
                    latestData?.survivalRate.toStringAsFixed(1) ?? '-',
                    '%',
                    Icons.trending_up,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryItem(
                    'Biomassa',
                    latestData?.totalBiomass.toStringAsFixed(1) ?? '-',
                    'kg',
                    Icons.inventory_2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, String unit, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.blue[700],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(SamplingData data) {
    // Calculate current fish count
    int currentFishCount = (initialStockCount * data.survivalRate / 100).toInt();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey[300]!,
              Colors.grey[350]!,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          DateFormat('d MMMM yyyy').format(data.date),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Sample: ${data.sampleCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tombol Edit
                    InkWell(
                      onTap: () => _navigateToEditPage(data),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Tombol Delete
                    InkWell(
                      onTap: () => _confirmDelete(data),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDataRow('Berat Rata-rata',
                '${data.averageWeight.toStringAsFixed(1)} gram'),
            const SizedBox(height: 8),
            _buildDataRow(
                'Biomassa', '${data.totalBiomass.toStringAsFixed(1)} kg'),
            const SizedBox(height: 8),
            _buildDataRow('Jumlah Ikan', '$currentFishCount ekor'),
            const SizedBox(height: 8),
            _buildDataRow('Survival Rate (SR)',
                '${data.survivalRate.toStringAsFixed(1)}%',
                valueColor: _getSRColor(data.survivalRate)),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.grey[900],
          ),
        ),
      ],
    );
  }

  Color _getSRColor(double sr) {
    if (sr >= 90) return Colors.green[700]!;
    if (sr >= 80) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Belum ada data sampling',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tekan tombol + untuk menambah data',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Navigasi ke halaman input untuk tambah data baru
  void _navigateToInputPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SamplingInputPage(
          initialStockCount: initialStockCount,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      // Save to Firebase
      await _saveToFirebase(result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Data sampling berhasil disimpan ke Firebase'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Navigasi ke halaman input untuk edit data
  void _navigateToEditPage(SamplingData data) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SamplingInputPage(
          initialStockCount: initialStockCount,
          editMode: true,
          existingData: data,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      // Update to Firebase
      await _updateToFirebase(data.id!, result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Data sampling berhasil diperbarui'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Konfirmasi sebelum menghapus
  void _confirmDelete(SamplingData data) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Konfirmasi Hapus'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Apakah Anda yakin ingin menghapus data sampling ini?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tanggal: ${DateFormat('d MMMM yyyy').format(data.date)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ABW: ${data.averageWeight.toStringAsFixed(1)} gram',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SR: ${data.survivalRate.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Data yang dihapus tidak dapat dikembalikan.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteFromFirebase(data.id!);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
  }

  // Simpan data baru ke Firebase
  Future<void> _saveToFirebase(Map<String, dynamic> result) async {
    const String deviceId = 'ESP32_N3FARM_001';

    try {
      // Save Initial Stock jika berubah
      if (result.containsKey('initialStock')) {
        await _database
            .child('$deviceId/farmData/initialStock')
            .set(result['initialStock']);
      }

      // Save Sampling Data
      if (result.containsKey('samplingData')) {
        final SamplingData data = result['samplingData'];
        final timestamp = data.date.millisecondsSinceEpoch;

        await _database
            .child('$deviceId/samplingData/sample_$timestamp')
            .set(data.toFirebase());
      }
    } catch (e) {
      print('Error saving to Firebase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error menyimpan data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Update data yang sudah ada ke Firebase
  Future<void> _updateToFirebase(String id, Map<String, dynamic> result) async {
    const String deviceId = 'ESP32_N3FARM_001';

    try {
      // Update Initial Stock jika berubah
      if (result.containsKey('initialStock')) {
        await _database
            .child('$deviceId/farmData/initialStock')
            .set(result['initialStock']);
      }

      // Update Sampling Data
      if (result.containsKey('samplingData')) {
        final SamplingData data = result['samplingData'];

        await _database
            .child('$deviceId/samplingData/$id')
            .update(data.toFirebase());
      }
    } catch (e) {
      print('Error updating to Firebase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error memperbarui data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Hapus data dari Firebase
  Future<void> _deleteFromFirebase(String id) async {
    const String deviceId = 'ESP32_N3FARM_001';

    try {
      await _database
          .child('$deviceId/samplingData/$id')
          .remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Data sampling berhasil dihapus'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error deleting from Firebase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error menghapus data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Cancel Firebase listeners
    _initialStockListener?.cancel();
    _samplingDataListener?.cancel();
    super.dispose();
  }
}

// Model untuk Sampling Data dengan Firebase integration
class SamplingData {
  final String? id;
  final DateTime date;
  final int sampleCount;
  final double averageWeight; // gram
  final double totalBiomass; // kg
  final double survivalRate; // %

  SamplingData({
    this.id,
    required this.date,
    required this.sampleCount,
    required this.averageWeight,
    required this.totalBiomass,
    required this.survivalRate,
  });

  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'date': date.toIso8601String(),
      'timestamp': date.millisecondsSinceEpoch,
      'sample_count': sampleCount,
      'average_weight': averageWeight,
      'total_biomass': totalBiomass,
      'survival_rate': survivalRate,
    };
  }

  // Create from Firebase data
  factory SamplingData.fromFirebase(String id, Map<dynamic, dynamic> data) {
    return SamplingData(
      id: id,
      date: DateTime.parse(data['date'].toString()),
      sampleCount: (data['sample_count'] as num).toInt(),
      averageWeight: (data['average_weight'] as num).toDouble(),
      totalBiomass: (data['total_biomass'] as num).toDouble(),
      survivalRate: (data['survival_rate'] as num).toDouble(),
    );
  }

  // Legacy format (untuk compatibility)
  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'sample_count': sampleCount,
      'average_weight': averageWeight,
      'total_biomass': totalBiomass,
      'survival_rate': survivalRate,
    };
  }

  factory SamplingData.fromJson(Map<String, dynamic> json) {
    return SamplingData(
      date: DateTime.parse(json['date']),
      sampleCount: json['sample_count'],
      averageWeight: json['average_weight'].toDouble(),
      totalBiomass: json['total_biomass'].toDouble(),
      survivalRate: json['survival_rate'].toDouble(),
    );
  }
}