import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';

class PhControlHistoryPage extends StatefulWidget {
  const PhControlHistoryPage({Key? key}) : super(key: key);

  @override
  State<PhControlHistoryPage> createState() => _PhControlHistoryPageState();
}

class _PhControlHistoryPageState extends State<PhControlHistoryPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  // StreamSubscription untuk cancel listener
  StreamSubscription? _phControlLogListener;
  
  // Data riwayat kontrol pH dari Firebase
  List<PhControlLog> phControlHistory = [];
  
  // Loading state
  bool isLoading = true;
  
  // Filter
  String selectedFilter = 'Semua'; // 'Semua', 'ASAM', 'BASA'
  
  @override
  void initState() {
    super.initState();
    _setupFirebaseListener();
  }
  
  void _setupFirebaseListener() {
    const String deviceId = 'ESP32_N3FARM_001';
    
    // Listener untuk pH Control Log
    _phControlLogListener = _database
        .child('$deviceId/phControlLog')
        .orderByChild('timestamp')
        .onValue
        .listen((event) {
      if (!mounted) return;
      
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        
        List<PhControlLog> tempList = [];
        data.forEach((key, value) {
          try {
            final logData = PhControlLog.fromFirebase(
              key.toString(),
              value as Map<dynamic, dynamic>,
            );
            tempList.add(logData);
          } catch (e) {
            print('Error parsing pH control log: $e');
          }
        });
        
        // Sort by timestamp descending (terbaru di atas)
        tempList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        setState(() {
          phControlHistory = tempList;
          isLoading = false;
        });
      } else {
        setState(() {
          phControlHistory = [];
          isLoading = false;
        });
      }
    }, onError: (error) {
      print('Error loading pH control log: $error');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }
  
  List<PhControlLog> get filteredHistory {
    if (selectedFilter == 'Semua') {
      return phControlHistory;
    }
    return phControlHistory.where((log) => log.type == selectedFilter).toList();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Riwayat Kontrol pH',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
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
                      _buildFilterChips(),
                      const SizedBox(height: 16),
                      _buildSectionHeader('Riwayat Kontrol pH'),
                      const SizedBox(height: 12),
                      if (filteredHistory.isEmpty)
                        _buildEmptyState()
                      else
                        ...filteredHistory.map((log) => _buildLogCard(log)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
  
  Widget _buildSummaryCard() {
    int totalLogs = phControlHistory.length;
    int asamCount = phControlHistory.where((log) => log.type == 'ASAM').length;
    int basaCount = phControlHistory.where((log) => log.type == 'BASA').length;
    
    // Get latest log
    PhControlLog? latestLog = phControlHistory.isNotEmpty ? phControlHistory.first : null;
    
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
                  Icons.science,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ringkasan Kontrol pH',
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
                    'Total Log',
                    totalLogs.toString(),
                    'kali',
                    Icons.list_alt,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryItem(
                    'Penambah Asam',
                    asamCount.toString(),
                    'kali',
                    Icons.arrow_downward,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Penambah Basa',
                    basaCount.toString(),
                    'kali',
                    Icons.arrow_upward,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryItem(
                    'pH Terakhir',
                    latestLog?.phBefore.toStringAsFixed(2) ?? '-',
                    '',
                    Icons.water_drop,
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
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChips() {
    return Row(
      children: [
        _buildFilterChip('Semua', phControlHistory.length),
        const SizedBox(width: 8),
        _buildFilterChip('ASAM', phControlHistory.where((log) => log.type == 'ASAM').length),
        const SizedBox(width: 8),
        _buildFilterChip('BASA', phControlHistory.where((log) => log.type == 'BASA').length),
      ],
    );
  }
  
  Widget _buildFilterChip(String label, int count) {
    bool isSelected = selectedFilter == label;
    return Expanded(
      child: FilterChip(
        label: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.3) : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        selected: isSelected,
        onSelected: (bool selected) {
          setState(() {
            selectedFilter = label;
          });
        },
        backgroundColor: Colors.white,
        selectedColor: label == 'ASAM' ? Colors.orange[600] : 
                       label == 'BASA' ? Colors.blue[600] : Colors.grey[600],
        checkmarkColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
  
  Widget _buildLogCard(PhControlLog log) {
    Color cardColor = log.type == 'ASAM' ? Colors.orange[50]! : Colors.blue[50]!;
    Color accentColor = log.type == 'ASAM' ? Colors.orange[700]! : Colors.blue[700]!;
    IconData icon = log.type == 'ASAM' ? Icons.arrow_downward : Icons.arrow_upward;
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: cardColor,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dosing ${log.type}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                        Text(
                          DateFormat('d MMM yyyy, HH:mm:ss').format(log.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accentColor, width: 1),
                  ),
                  child: Text(
                    'pH ${log.phBefore.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    'Volume Dosing',
                    '${log.volumeML.toStringAsFixed(0)} mL',
                    Icons.opacity,
                  ),
                  const Divider(height: 16),
                  _buildDetailRow(
                    'pH Sebelum',
                    log.phBefore.toStringAsFixed(2),
                    Icons.water_drop,
                  ),
                  const Divider(height: 16),
                  _buildDetailRow(
                    'Timestamp',
                    DateFormat('dd/MM/yyyy HH:mm:ss').format(log.timestamp),
                    Icons.access_time,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(
              Icons.science_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              selectedFilter == 'Semua' 
                  ? 'Belum ada riwayat kontrol pH'
                  : 'Tidak ada data untuk filter $selectedFilter',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Riwayat kontrol pH akan muncul di sini',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.blue[700]),
              const SizedBox(width: 8),
              const Text('Filter Data'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFilterOption('Semua', Icons.list_alt),
              _buildFilterOption('ASAM', Icons.arrow_downward),
              _buildFilterOption('BASA', Icons.arrow_upward),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildFilterOption(String filter, IconData icon) {
    bool isSelected = selectedFilter == filter;
    Color color = filter == 'ASAM' ? Colors.orange[700]! : 
                  filter == 'BASA' ? Colors.blue[700]! : Colors.grey[700]!;
    
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        filter,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check, color: color) : null,
      selected: isSelected,
      selectedTileColor: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onTap: () {
        setState(() {
          selectedFilter = filter;
        });
        Navigator.of(context).pop();
      },
    );
  }
  
  @override
  void dispose() {
    _phControlLogListener?.cancel();
    super.dispose();
  }
}

// Model untuk pH Control Log
class PhControlLog {
  final String id;
  final DateTime timestamp;
  final String type; // 'ASAM' atau 'BASA'
  final double phBefore;
  final double volumeML;
  
  PhControlLog({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.phBefore,
    required this.volumeML,
  });
  
  // Create from Firebase data
  factory PhControlLog.fromFirebase(String id, Map<dynamic, dynamic> data) {
    // Parse timestamp dari string ISO atau langsung dari milliseconds
    DateTime timestamp;
    try {
      if (data['timestamp'] is String) {
        timestamp = DateTime.parse(data['timestamp']);
      } else if (data['timestamp'] is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp']);
      } else {
        timestamp = DateTime.now();
      }
    } catch (e) {
      print('Error parsing timestamp: $e');
      timestamp = DateTime.now();
    }
    
    return PhControlLog(
      id: id,
      timestamp: timestamp,
      type: data['type']?.toString() ?? 'UNKNOWN',
      phBefore: (data['phBefore'] as num?)?.toDouble() ?? 7.0,
      volumeML: (data['volumeML'] as num?)?.toDouble() ?? 0.0,
    );
  }
  
  // Convert to Firebase format
  Map<String, dynamic> toFirebase() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'phBefore': phBefore,
      'volumeML': volumeML,
    };
  }
}
