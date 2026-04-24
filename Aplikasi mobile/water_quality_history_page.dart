import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class WaterQualityHistoryPage extends StatefulWidget {
  const WaterQualityHistoryPage({Key? key}) : super(key: key);

  @override
  State<WaterQualityHistoryPage> createState() => _WaterQualityHistoryPageState();
}

class _WaterQualityHistoryPageState extends State<WaterQualityHistoryPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  DateTime selectedDate = DateTime.now();
  List<WaterQualityData> historyData = [];
  bool isLoading = false;
  
  // Statistik harian
  double? avgPH;
  double? minPH;
  double? maxPH;
  
  double? avgTemp;
  double? minTemp;
  double? maxTemp;
  
  double? avgTurbidity;
  double? minTurbidity;
  double? maxTurbidity;
  
  int warningCount = 0;

  @override
  void initState() {
    super.initState();
    _loadHistoryData();
  }

  Future<void> _loadHistoryData() async {
    setState(() {
      isLoading = true;
    });

    try {
      const String deviceId = 'ESP32_N3FARM_001';
      final String dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
      
      final snapshot = await _database
          .child('$deviceId/waterQualityHistory/$dateKey')
          .get();

      if (snapshot.exists && mounted) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        List<WaterQualityData> tempList = [];
        data.forEach((timestamp, value) {
          try {
            final record = WaterQualityData.fromFirebase(
              timestamp.toString(),
              value as Map<dynamic, dynamic>,
            );
            tempList.add(record);
          } catch (e) {
            print('Error parsing data: $e');
          }
        });

        // Sort by timestamp
        tempList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Calculate statistics
        if (tempList.isNotEmpty) {
          _calculateStatistics(tempList);
        }

        setState(() {
          historyData = tempList;
          isLoading = false;
        });
      } else {
        setState(() {
          historyData = [];
          isLoading = false;
          _resetStatistics();
        });
      }
    } catch (e) {
      print('Error loading history: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          _resetStatistics();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat data: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _calculateStatistics(List<WaterQualityData> data) {
    // pH Statistics
    final phValues = data.map((d) => d.pH).toList();
    avgPH = phValues.reduce((a, b) => a + b) / phValues.length;
    minPH = phValues.reduce((a, b) => a < b ? a : b);
    maxPH = phValues.reduce((a, b) => a > b ? a : b);

    // Temperature Statistics
    final tempValues = data.map((d) => d.temperature).toList();
    avgTemp = tempValues.reduce((a, b) => a + b) / tempValues.length;
    minTemp = tempValues.reduce((a, b) => a < b ? a : b);
    maxTemp = tempValues.reduce((a, b) => a > b ? a : b);

    // Turbidity Statistics
    final turbidityValues = data.map((d) => d.turbidity).toList();
    avgTurbidity = turbidityValues.reduce((a, b) => a + b) / turbidityValues.length;
    minTurbidity = turbidityValues.reduce((a, b) => a < b ? a : b);
    maxTurbidity = turbidityValues.reduce((a, b) => a > b ? a : b);

    // Count warnings
    warningCount = data.where((d) => 
      d.phWarning || d.tempWarning || d.turbidityWarning
    ).length;
  }

  void _resetStatistics() {
    avgPH = minPH = maxPH = null;
    avgTemp = minTemp = maxTemp = null;
    avgTurbidity = minTurbidity = maxTurbidity = null;
    warningCount = 0;
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue[700]!,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _loadHistoryData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Ringkasan Kualitas Air',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Pilih Tanggal',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Selector
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tanggal Dipilih',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy').format(selectedDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: historyData.isEmpty ? Colors.grey[200] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${historyData.length} data',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: historyData.isEmpty ? Colors.grey[600] : Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: isLoading
                ? Center(
                    child: CircularProgressIndicator(color: Colors.blue[700]),
                  )
                : historyData.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadHistoryData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Summary Cards
                                _buildSummaryCards(),
                                const SizedBox(height: 24),
                                
                                // pH Chart
                                _buildSectionHeader('Grafik pH', Icons.water_drop),
                                const SizedBox(height: 12),
                                _buildPHChart(),
                                const SizedBox(height: 24),
                                
                                // Temperature Chart
                                _buildSectionHeader('Grafik Suhu', Icons.thermostat),
                                const SizedBox(height: 12),
                                _buildTemperatureChart(),
                                const SizedBox(height: 24),
                                
                                // Turbidity Chart
                                _buildSectionHeader('Grafik Kekeruhan', Icons.opacity),
                                const SizedBox(height: 12),
                                _buildTurbidityChart(),
                                const SizedBox(height: 24),
                                
                                // Data Table
                                _buildSectionHeader('Detail Data', Icons.table_chart),
                                const SizedBox(height: 12),
                                _buildDataTable(),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        // pH Summary
        _buildStatCard(
          'pH Air',
          avgPH ?? 0,
          minPH ?? 0,
          maxPH ?? 0,
          '',
          Colors.blue,
          Icons.water_drop,
        ),
        const SizedBox(height: 12),
        
        // Temperature Summary
        _buildStatCard(
          'Suhu Air',
          avgTemp ?? 0,
          minTemp ?? 0,
          maxTemp ?? 0,
          '°C',
          Colors.orange,
          Icons.thermostat,
        ),
        const SizedBox(height: 12),
        
        // Turbidity Summary
        _buildStatCard(
          'Kekeruhan',
          avgTurbidity ?? 0,
          minTurbidity ?? 0,
          maxTurbidity ?? 0,
          'NTU',
          Colors.green,
          Icons.opacity,
        ),
        const SizedBox(height: 12),
        
        // Warning Card
        _buildWarningCard(),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    double avg,
    double min,
    double max,
    String unit,
    MaterialColor color,
    IconData icon,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color[700], size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Rata-rata', avg, unit, color),
                Container(
                  height: 40,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildStatItem('Min', min, unit, color),
                Container(
                  height: 40,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildStatItem('Max', max, unit, color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, double value, String unit, MaterialColor color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(2)}$unit',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color[700],
          ),
        ),
      ],
    );
  }

  Widget _buildWarningCard() {
    final totalDataPoints = historyData.length;
    final normalDataPoints = totalDataPoints - warningCount;
    final normalPercentage = totalDataPoints > 0 
        ? (normalDataPoints / totalDataPoints * 100) 
        : 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: warningCount == 0 ? Colors.green[50] : Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                warningCount == 0 ? Icons.check_circle : Icons.warning,
                color: warningCount == 0 ? Colors.green[700] : Colors.orange[700],
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Kualitas Air',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    warningCount == 0 
                        ? 'Semua Parameter Normal' 
                        : '$warningCount dari $totalDataPoints data warning',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${normalPercentage.toStringAsFixed(1)}% waktu dalam kondisi ideal',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue[700]),
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

  Widget _buildPHChart() {
    if (historyData.isEmpty) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300],
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: historyData.length > 12 
                        ? (historyData.length / 6).ceilToDouble() 
                        : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < historyData.length) {
                        final time = DateFormat('HH:mm').format(
                          historyData[index].recordedAt
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            time,
                            style: const TextStyle(fontSize: 9),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey[300]!),
              ),
              minY: 0,
              maxY: 14,
              lineBarsData: [
                LineChartBarData(
                  spots: historyData.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.pH);
                  }).toList(),
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      final hasWarning = historyData[index].phWarning;
                      return FlDotCirclePainter(
                        radius: hasWarning ? 5 : 3,
                        color: hasWarning ? Colors.red : Colors.blue,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.blue.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemperatureChart() {
    if (historyData.isEmpty) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300],
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: historyData.length > 12 
                        ? (historyData.length / 6).ceilToDouble() 
                        : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < historyData.length) {
                        final time = DateFormat('HH:mm').format(
                          historyData[index].recordedAt
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            time,
                            style: const TextStyle(fontSize: 9),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}°C',
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey[300]!),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: historyData.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.temperature);
                  }).toList(),
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      final hasWarning = historyData[index].tempWarning;
                      return FlDotCirclePainter(
                        radius: hasWarning ? 5 : 3,
                        color: hasWarning ? Colors.red : Colors.orange,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.orange.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTurbidityChart() {
    if (historyData.isEmpty) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300],
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: historyData.length > 12 
                        ? (historyData.length / 6).ceilToDouble() 
                        : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < historyData.length) {
                        final time = DateFormat('HH:mm').format(
                          historyData[index].recordedAt
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            time,
                            style: const TextStyle(fontSize: 9),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}',
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey[300]!),
              ),
              minY: 0,
              lineBarsData: [
                LineChartBarData(
                  spots: historyData.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.turbidity);
                  }).toList(),
                  isCurved: true,
                  color: Colors.green,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      final hasWarning = historyData[index].turbidityWarning;
                      return FlDotCirclePainter(
                        radius: hasWarning ? 5 : 3,
                        color: hasWarning ? Colors.red : Colors.green,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.green.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildTableHeader('Waktu', flex: 2),
                  _buildTableHeader('pH', flex: 1),
                  _buildTableHeader('Suhu', flex: 1),
                  _buildTableHeader('NTU', flex: 1),
                ],
              ),
            ),
            const SizedBox(height: 8),
            
            // Table Rows
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: historyData.length,
              itemBuilder: (context, index) {
                return _buildTableRow(historyData[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.blue[900],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableRow(WaterQualityData data) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('HH:mm:ss').format(data.recordedAt),
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data.phWarning)
                  Icon(Icons.warning, size: 10, color: Colors.red[700]),
                const SizedBox(width: 2),
                Text(
                  data.pH.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: data.phWarning ? Colors.red[700] : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data.tempWarning)
                  Icon(Icons.warning, size: 10, color: Colors.red[700]),
                const SizedBox(width: 2),
                Text(
                  '${data.temperature.toStringAsFixed(1)}°',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: data.tempWarning ? Colors.red[700] : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data.turbidityWarning)
                  Icon(Icons.warning, size: 10, color: Colors.red[700]),
                const SizedBox(width: 2),
                Text(
                  data.turbidity.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: data.turbidityWarning ? Colors.red[700] : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.water_drop_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Tidak Ada Data',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada data kualitas air untuk tanggal ini.\nPilih tanggal lain atau tunggu sistem merekam data.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _selectDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: const Text('Pilih Tanggal Lain'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Model Class
class WaterQualityData {
  final String timestamp;
  final double pH;
  final String phStatus;
  final bool phWarning;
  final double temperature;
  final String tempStatus;
  final bool tempWarning;
  final double turbidity;
  final int turbidityNTU;
  final String turbidityStatus;
  final bool turbidityWarning;
  final DateTime recordedAt;

  WaterQualityData({
    required this.timestamp,
    required this.pH,
    required this.phStatus,
    required this.phWarning,
    required this.temperature,
    required this.tempStatus,
    required this.tempWarning,
    required this.turbidity,
    required this.turbidityNTU,
    required this.turbidityStatus,
    required this.turbidityWarning,
    required this.recordedAt,
  });

  factory WaterQualityData.fromFirebase(
      String timestamp, Map<dynamic, dynamic> data) {
    return WaterQualityData(
      timestamp: timestamp,
      pH: (data['pH'] ?? 7.0).toDouble(),
      phStatus: data['phStatus']?.toString() ?? 'Unknown',
      phWarning: data['phWarning'] ?? false,
      temperature: (data['temp'] ?? 0.0).toDouble(),
      tempStatus: data['tempStatus']?.toString() ?? 'Unknown',
      tempWarning: data['tempWarning'] ?? false,
      turbidity: (data['turbidity'] ?? 0.0).toDouble(),
      turbidityNTU: (data['turbidityNTU'] ?? 0).toInt(),
      turbidityStatus: data['turbidityStatus']?.toString() ?? 'Unknown',
      turbidityWarning: data['turbidityWarning'] ?? false,
      recordedAt: DateTime.parse(data['recordedAt'].toString()),
    );
  }
}
