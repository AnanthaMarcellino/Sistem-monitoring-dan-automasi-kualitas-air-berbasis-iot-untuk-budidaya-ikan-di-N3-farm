import 'package:flutter/material.dart';
import 'sampling_history_page.dart';

class SamplingInputPage extends StatefulWidget {
  final int initialStockCount;
  final bool editMode;
  final SamplingData? existingData;

  const SamplingInputPage({
    Key? key,
    required this.initialStockCount,
    this.editMode = false,
    this.existingData,
  }) : super(key: key);

  @override
  State<SamplingInputPage> createState() => _SamplingInputPageState();
}

class _SamplingInputPageState extends State<SamplingInputPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _initialStockController = TextEditingController();
  final TextEditingController _currentCountController = TextEditingController();
  final TextEditingController _sampleCountController = TextEditingController();
  final TextEditingController _totalBiomassController = TextEditingController();

  // List untuk input berat individual
  List<TextEditingController> _weightControllers = [];
  List<double> _weights = [];

  // Calculated values
  double _averageWeight = 0;
  double _survivalRate = 0;
  double _totalBiomass = 0;

  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    if (widget.editMode && widget.existingData != null) {
      // Mode Edit - Load existing data
      _loadExistingData();
    } else {
      // Mode Tambah - Initialize kosong
      _dateController.text = _formatDate(selectedDate);
      _initialStockController.text = widget.initialStockCount.toString();
      _addWeightField();
    }
  }

  void _loadExistingData() {
    final data = widget.existingData!;

    setState(() {
      selectedDate = data.date;
      _dateController.text = _formatDate(data.date);
      _initialStockController.text = widget.initialStockCount.toString();

      // Hitung current count dari SR
      int currentCount = (widget.initialStockCount * data.survivalRate / 100).toInt();
      _currentCountController.text = currentCount.toString();

      // Load calculated values
      _averageWeight = data.averageWeight;
      _survivalRate = data.survivalRate;
      _totalBiomass = data.totalBiomass;
      _totalBiomassController.text = data.totalBiomass.toStringAsFixed(2);

      // Inisialisasi weight fields berdasarkan average weight dan sample count
      // Karena kita tidak menyimpan individual weights, kita isi dengan average weight
      for (int i = 0; i < data.sampleCount; i++) {
        var controller = TextEditingController(text: data.averageWeight.toStringAsFixed(1));
        _weightControllers.add(controller);
        _weights.add(data.averageWeight);
      }

      _sampleCountController.text = data.sampleCount.toString();
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _initialStockController.dispose();
    _currentCountController.dispose();
    _sampleCountController.dispose();
    _totalBiomassController.dispose();
    for (var controller in _weightControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _addWeightField() {
    setState(() {
      _weightControllers.add(TextEditingController());
    });
  }

  void _removeWeightField(int index) {
    if (_weightControllers.length > 1) {
      setState(() {
        _weightControllers[index].dispose();
        _weightControllers.removeAt(index);
        _calculateAverage();
      });
    }
  }

  void _calculateAverage() {
    _weights.clear();
    double sum = 0;
    int validCount = 0;

    for (var controller in _weightControllers) {
      if (controller.text.isNotEmpty) {
        double? weight = double.tryParse(controller.text);
        if (weight != null && weight > 0) {
          _weights.add(weight);
          sum += weight;
          validCount++;
        }
      }
    }

    setState(() {
      _averageWeight = validCount > 0 ? sum / validCount : 0;
      _sampleCountController.text = validCount.toString();
      _calculateSurvivalRate();
      _calculateBiomass(); // Calculate biomass automatically
    });
  }

  void _calculateBiomass() {
    int currentCount = int.tryParse(_currentCountController.text) ?? 0;

    if (_averageWeight > 0 && currentCount > 0) {
      // Formula: Total Biomassa (kg) = (ABW (gram) × Jumlah Ikan) / 1000
      setState(() {
        _totalBiomass = (_averageWeight * currentCount) / 1000;
        _totalBiomassController.text = _totalBiomass.toStringAsFixed(2);
      });
    } else {
      setState(() {
        _totalBiomass = 0;
        _totalBiomassController.text = '';
      });
    }
  }

  void _calculateSurvivalRate() {
    int initialStock = int.tryParse(_initialStockController.text) ?? 0;
    int currentCount = int.tryParse(_currentCountController.text) ?? 0;

    if (initialStock > 0 && currentCount > 0) {
      setState(() {
        _survivalRate = (currentCount / initialStock) * 100;
      });
    } else {
      setState(() {
        _survivalRate = 0;
      });
    }

    // Recalculate biomass when fish count changes
    _calculateBiomass();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          widget.editMode ? 'Edit Data Penimbangan Ikan...' : 'Input Data Penimbangan Ikan...',
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge untuk menunjukkan mode
                if (widget.editMode)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 16, color: Colors.orange[800]),
                        const SizedBox(width: 6),
                        Text(
                          'Mode Edit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Card untuk form
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tanggal Sampling
                        _buildSectionTitle('Tanggal Sampling'),
                        const SizedBox(height: 12),
                        _buildDateField(),

                        const SizedBox(height: 20),

                        // Jumlah Tebar Awal
                        _buildSectionTitle('Jumlah Tebar Awal (ekor)'),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _initialStockController,
                          hint: 'Masukkan jumlah ikan saat tebar awal',
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _calculateSurvivalRate(),
                        ),

                        const SizedBox(height: 20),

                        // Jumlah Ikan Saat Ini
                        _buildSectionTitle('Jumlah Ikan Saat Ini (ekor)'),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _currentCountController,
                          hint: 'Masukkan jumlah ikan saat ini',
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _calculateSurvivalRate(),
                        ),

                        const SizedBox(height: 20),

                        // Jumlah Sample Ikan
                        _buildSectionTitle('Jumlah Sample Ikan'),
                        const SizedBox(height: 8),
                        Text(
                          'Berat ${_weights.length} ekor ikan (gram)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Dynamic weight input fields
                        ..._buildWeightFields(),

                        const SizedBox(height: 12),

                        // Add more button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addWeightField,
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Input Berat'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue[700],
                              side: BorderSide(color: Colors.blue[700]!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Result Card (includes Total Biomassa input)
                if (_averageWeight > 0 || _survivalRate > 0)
                  _buildResultCard(),

                const SizedBox(height: 20),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.editMode ? Colors.orange[700] : Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.editMode ? Icons.check_circle : Icons.save),
                        const SizedBox(width: 8),
                        Text(
                          widget.editMode ? 'Perbarui Data' : 'Simpan Data',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Field ini wajib diisi';
        }
        return null;
      },
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _dateController,
      readOnly: true,
      decoration: InputDecoration(
        hintText: 'Pilih tanggal sampling',
        filled: true,
        fillColor: Colors.grey[100],
        prefixIcon: Icon(Icons.calendar_today, color: Colors.blue[700]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onTap: _selectDate,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Tanggal wajib dipilih';
        }
        return null;
      },
    );
  }

  List<Widget> _buildWeightFields() {
    List<Widget> fields = [];
    for (int i = 0; i < _weightControllers.length; i++) {
      fields.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              // Number badge
              Container(
                width: 32,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Input field
              Expanded(
                child: TextFormField(
                  controller: _weightControllers[i],
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateAverage(),
                  decoration: InputDecoration(
                    hintText: 'Berat (gram)',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              // Delete button
              if (_weightControllers.length > 1) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _removeWeightField(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 40,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.delete,
                      color: Colors.red[700],
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return fields;
  }

  Widget _buildResultCard() {
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
              Colors.green[500]!,
              Colors.green[700]!,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.assessment,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Hasil Perhitungan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Average Weight
            _buildResultRow(
              'Berat Rata-rata (ABW)',
              '${_averageWeight.toStringAsFixed(1)} gram',
              Icons.monitor_weight,
            ),

            const SizedBox(height: 12),

            // Survival Rate
            _buildResultRow(
              'Survival Rate (SR)',
              '${_survivalRate.toStringAsFixed(1)}%',
              Icons.trending_up,
              valueColor: _getSRColor(_survivalRate),
            ),

            const SizedBox(height: 12),

            // Sample Count
            _buildResultRow(
              'Jumlah Sample',
              '${_weights.length} ekor',
              Icons.pets,
            ),

            const SizedBox(height: 16),

            // Total Biomassa Input Field (Auto-calculated)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2,
                        color: Colors.green[800],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total Biomassa (kg)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[700],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'AUTO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green[700]!,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _totalBiomass > 0
                              ? _totalBiomass.toStringAsFixed(2)
                              : 'Menunggu input...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _totalBiomass > 0
                                ? Colors.grey[900]
                                : Colors.grey[500],
                          ),
                        ),
                        Text(
                          'kg',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_totalBiomass > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Formula: ABW × Jumlah Ikan ÷ 1000',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value, IconData icon, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.green[800], size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.grey[900],
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

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue[700]!,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  void _saveData() {
    if (_formKey.currentState!.validate()) {
      if (_weights.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Masukkan minimal 1 berat ikan untuk sample'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_totalBiomass <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Total biomassa belum terhitung. Pastikan semua data sudah diisi.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final samplingData = SamplingData(
        date: selectedDate,
        sampleCount: _weights.length,
        averageWeight: _averageWeight,
        totalBiomass: _totalBiomass,
        survivalRate: _survivalRate,
      );

      final result = {
        'initialStock': int.parse(_initialStockController.text),
        'samplingData': samplingData,
      };

      Navigator.pop(context, result);
    }
  }
}