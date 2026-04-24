import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class GrowthMetricsPage extends StatefulWidget {
  const GrowthMetricsPage({Key? key}) : super(key: key);

  @override
  State<GrowthMetricsPage> createState() => _GrowthMetricsPageState();
}

class _GrowthMetricsPageState extends State<GrowthMetricsPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  StreamSubscription? _initialStockListener;
  StreamSubscription? _samplingDataListener;

  int initialStockCount = 0;
  List<SamplingData> samplingHistory = [];
  List<GrowthMetric> growthMetrics = [];

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupFirebaseListeners();
  }

  void _setupFirebaseListeners() {
    const String deviceId = 'ESP32_N3FARM_001';

    _initialStockListener = _database
        .child('$deviceId/farmData/initialStock')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.value != null) {
        setState(() {
          initialStockCount = (event.snapshot.value as num).toInt();
        });
      }
    });

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

        tempList.sort((a, b) => a.date.compareTo(b.date));

        setState(() {
          samplingHistory = tempList;
          _calculateGrowthMetrics();
          isLoading = false;
        });
      } else {
        setState(() {
          samplingHistory = [];
          growthMetrics = [];
          isLoading = false;
        });
      }
    });
  }

  void _calculateGrowthMetrics() {
    if (samplingHistory.isEmpty) {
      growthMetrics = [];
      return;
    }

    List<GrowthMetric> metrics = [];

    for (int i = 0; i < samplingHistory.length; i++) {
      final current = samplingHistory[i];

      if (i == 0) {
        metrics.add(GrowthMetric(
          date: current.date,
          abw: current.averageWeight,
          sr: current.survivalRate,
          biomass: current.totalBiomass,
          adg: 0.0,
          sgr: 0.0,
          biomassGain: 0.0,
          daysSinceStart: 0,
        ));
      } else {
        final previous = samplingHistory[i - 1];
        final days = current.date.difference(previous.date).inDays;

        final adg = days > 0 ? (current.averageWeight - previous.averageWeight) / days : 0.0;
        final sgr = days > 0 ? ((math.log(current.averageWeight) -
            math.log(previous.averageWeight)) / days) * 100 : 0.0;
        final biomassGain = current.totalBiomass - previous.totalBiomass;
        final totalDays = current.date.difference(samplingHistory[0].date).inDays;

        metrics.add(GrowthMetric(
          date: current.date,
          abw: current.averageWeight,
          sr: current.survivalRate,
          biomass: current.totalBiomass,
          adg: adg,
          sgr: sgr,
          biomassGain: biomassGain,
          daysSinceStart: totalDays,
        ));
      }
    }

    growthMetrics = metrics;
  }

  @override
  Widget build(BuildContext context) {
    final avgADG = growthMetrics.isEmpty
        ? 0.0
        : growthMetrics.map((m) => m.adg).reduce((a, b) => a + b) /
        growthMetrics.length;

    final avgSGR = growthMetrics.isEmpty
        ? 0.0
        : growthMetrics.map((m) => m.sgr).reduce((a, b) => a + b) /
        growthMetrics.length;

    final latestMetric = growthMetrics.isNotEmpty ? growthMetrics.last : null;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Metrik Pertumbuhan',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: isLoading
          ? Center(
        child: CircularProgressIndicator(color: Colors.blue[700]),
      )
          : samplingHistory.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: () async {
          if (mounted) setState(() {});
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCards(avgADG, avgSGR, latestMetric),
                const SizedBox(height: 24),
                _buildSectionHeader('Grafik Pertumbuhan Berat (ABW)'),
                const SizedBox(height: 12),
                _buildWeightChart(),
                const SizedBox(height: 24),
                _buildSectionHeader('Grafik ADG (gram/hari)'),
                const SizedBox(height: 12),
                _buildADGChart(),
                const SizedBox(height: 24),
                _buildSectionHeader('Grafik Biomassa (kg)'),
                const SizedBox(height: 12),
                _buildBiomassChart(),
                const SizedBox(height: 24),
                _buildSectionHeader('Grafik Survival Rate (%)'),
                const SizedBox(height: 12),
                _buildSRChart(),
                const SizedBox(height: 24),
                _buildSectionHeader('Detail Metrik Pertumbuhan'),
                const SizedBox(height: 12),
                _buildMetricsTable(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(double avgADG, double avgSGR, GrowthMetric? latest) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'ADG Rata-rata',
                avgADG.toStringAsFixed(2),
                'gram/hari',
                Icons.trending_up,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'SGR Rata-rata',
                avgSGR.toStringAsFixed(2),
                '%/hari',
                Icons.show_chart,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'SR Terkini',
                latest?.sr.toStringAsFixed(1) ?? '-',
                '%',
                Icons.pets,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'Biomassa Terkini',
                latest?.biomass.toStringAsFixed(1) ?? '-',
                'kg',
                Icons.scale,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
      String label,
      String value,
      String unit,
      IconData icon,
      MaterialColor color,
      ) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.shade400, color.shade600],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildWeightChart() {
    if (growthMetrics.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final metric = growthMetrics[spot.x.toInt()];
                      return LineTooltipItem(
                        '${metric.abw.toStringAsFixed(1)} g',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  axisNameWidget: const Padding(
                    padding: EdgeInsets.only(top: 0.0),
                    child: Text('Tanggal', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < growthMetrics.length) {
                        final metric = growthMetrics[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.5,  // Rotasi 30 derajat supaya ga overlap
                            child: Text(
                              '${metric.date.day}/${metric.date.month}/${metric.date.year % 100}',
                              style: const TextStyle(fontSize: 9),
                            ),
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
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
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
                  spots: growthMetrics.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.abw);
                  }).toList(),
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: Colors.blue,
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

  Widget _buildADGChart() {
    final adgData = growthMetrics.where((m) => m.adg > 0).toList();
    if (adgData.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: adgData.map((m) => m.adg).reduce(math.max) * 1.2,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final metric = adgData[group.x.toInt()];
                    return BarTooltipItem(
                      '${metric.adg.toStringAsFixed(2)} g/hari',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < growthMetrics.length) {
                        final metric = growthMetrics[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.5,  // Rotasi 30 derajat supaya ga overlap
                            child: Text(
                              '${metric.date.day}/${metric.date.month}/${metric.date.year % 100}',
                              style: const TextStyle(fontSize: 9),
                            ),
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
                    reservedSize: 40,
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
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey[300]!),
              ),
              barGroups: adgData.asMap().entries.map((entry) {
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.adg,
                      color: Colors.green,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiomassChart() {
    if (growthMetrics.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final metric = growthMetrics[spot.x.toInt()];
                      return LineTooltipItem(
                        '${metric.biomass.toStringAsFixed(1)} kg',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  axisNameWidget: const Padding(
                    padding: EdgeInsets.only(top: 0.0),
                    child: Text('Tanggal', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < growthMetrics.length) {
                        final metric = growthMetrics[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.5,
                            child: Text(
                              '${metric.date.day}/${metric.date.month}/${metric.date.year % 100}',
                              style: const TextStyle(fontSize: 9),
                            ),
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
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
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
                  spots: growthMetrics.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.biomass);
                  }).toList(),
                  isCurved: true,
                  color: Colors.purple,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: Colors.purple,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.withOpacity(0.3),
                        Colors.purple.withOpacity(0.1),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
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

  Widget _buildSRChart() {
    if (growthMetrics.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              minY: 70,
              maxY: 100,
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final metric = growthMetrics[spot.x.toInt()];
                      return LineTooltipItem(
                        '${metric.sr.toStringAsFixed(1)}%',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 5,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  axisNameWidget: const Padding(
                    padding: EdgeInsets.only(top: 0.0),
                    child: Text('Tanggal', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < growthMetrics.length) {
                        final metric = growthMetrics[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.5,
                            child: Text(
                              '${metric.date.day}/${metric.date.month}/${metric.date.year % 100}',
                              style: const TextStyle(fontSize: 9),
                            ),
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
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}%',
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
                  spots: growthMetrics.asMap().entries.map((entry) {
                    return FlSpot(entry.key.toDouble(), entry.value.sr);
                  }).toList(),
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotSquarePainter(
                        size: 8,
                        color: Colors.orange,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildTableHeader('Tanggal', flex: 2),
                  _buildTableHeader('ADG', flex: 1),
                  _buildTableHeader('SGR', flex: 1),
                  _buildTableHeader('SR', flex: 1),
                  _buildTableHeader('Biomassa', flex: 2),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...growthMetrics.map((metric) => _buildTableRow(metric)),
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

  Widget _buildTableRow(GrowthMetric metric) {
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
              '${metric.date.day}/${metric.date.month}/${metric.date.year}',
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              metric.adg > 0 ? metric.adg.toStringAsFixed(2) : '-',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              metric.sgr > 0 ? metric.sgr.toStringAsFixed(2) : '-',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${metric.sr.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _getSRColor(metric.sr),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${metric.biomass.toStringAsFixed(1)} kg',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Belum Ada Data Pertumbuhan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tambahkan data sampling untuk melihat metrik pertumbuhan',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _initialStockListener?.cancel();
    _samplingDataListener?.cancel();
    super.dispose();
  }
}

// Models
class GrowthMetric {
  final DateTime date;
  final double abw;
  final double sr;
  final double biomass;
  final double adg;
  final double sgr;
  final double biomassGain;
  final int daysSinceStart;

  GrowthMetric({
    required this.date,
    required this.abw,
    required this.sr,
    required this.biomass,
    required this.adg,
    required this.sgr,
    required this.biomassGain,
    required this.daysSinceStart,
  });
}

class SamplingData {
  final String? id;
  final DateTime date;
  final int sampleCount;
  final double averageWeight;
  final double totalBiomass;
  final double survivalRate;

  SamplingData({
    this.id,
    required this.date,
    required this.sampleCount,
    required this.averageWeight,
    required this.totalBiomass,
    required this.survivalRate,
  });

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
}