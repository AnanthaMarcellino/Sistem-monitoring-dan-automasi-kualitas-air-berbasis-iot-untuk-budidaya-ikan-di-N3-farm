import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'feeding_schedule_page.dart';

class FeedingFormPage extends StatefulWidget {
  final bool isEdit;
  final FeedingSchedule? schedule;

  const FeedingFormPage({
    Key? key,
    required this.isEdit,
    this.schedule,
  }) : super(key: key);

  @override
  State<FeedingFormPage> createState() => _FeedingFormPageState();
}

class _FeedingFormPageState extends State<FeedingFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _timeController;
  late TextEditingController _weightController;

  // Form values
  TimeOfDay? selectedTime;
  double selectedWeight = 77.0; // Default 77 gram
  bool isEnabled = true;

  @override
  void initState() {
    super.initState();

    if (widget.isEdit && widget.schedule != null) {
      final schedule = widget.schedule!; // Assign ke local variable setelah null check

      // Parse existing time
      final timeParts = schedule.time.split(' ')[0].split(':');
      selectedTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
      _timeController = TextEditingController(text: schedule.time);

      // Set weight
      selectedWeight = schedule.weightGrams;
      _weightController = TextEditingController(
        text: schedule.weightGrams.toStringAsFixed(0),
      );

      // Set enabled status
      isEnabled = schedule.enabled;
    } else {
      _timeController = TextEditingController();
      _weightController = TextEditingController(text: '77');
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          widget.isEdit ? 'Edit Jadwal Pakan' : 'Tambah Jadwal Pakan',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
          ),
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
                        // Waktu Pemberian
                        _buildSectionTitle('Waktu Pemberian'),
                        const SizedBox(height: 12),
                        _buildTimeField(),

                        const SizedBox(height: 24),

                        // Berat Pakan
                        _buildSectionTitle('Berat Pakan (gram)'),
                        const SizedBox(height: 12),
                        _buildWeightField(),

                        const SizedBox(height: 16),

                        // Preset buttons
                        _buildWeightPresets(),

                        const SizedBox(height: 16),

                        // Info durasi servo
                        _buildDurationInfo(),

                        if (widget.isEdit) ...[
                          const SizedBox(height: 24),

                          // Status aktif/nonaktif
                          _buildStatusSwitch(),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Action buttons
                _buildActionButtons(),
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
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildTimeField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: _timeController,
        readOnly: true,
        onTap: _selectTime,
        decoration: InputDecoration(
          hintText: 'Pilih waktu pemberian pakan',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: Icon(
            Icons.access_time,
            color: Colors.grey[700],
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Waktu pemberian harus diisi';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildWeightField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: _weightController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) {
          if (value.isNotEmpty) {
            setState(() {
              selectedWeight = double.tryParse(value) ?? 77.0;
            });
          }
        },
        decoration: InputDecoration(
          hintText: 'Masukkan berat pakan',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'gram',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.monitor_weight_outlined,
                  color: Colors.grey[700],
                ),
              ],
            ),
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Berat pakan harus diisi';
          }
          final weight = double.tryParse(value);
          if (weight == null || weight <= 0) {
            return 'Berat harus lebih dari 0 gram';
          }
          if (weight > 150) {
            return 'Berat maksimal 150 gram';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildWeightPresets() {
    final presets = [
      {'label': '20g', 'value': 20.0},
      {'label': '30g', 'value': 30.0},
      {'label': '50g', 'value': 50.0},
      {'label': '70g', 'value': 70.0},
      {'label': '100g', 'value': 100.0},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preset Berat Pakan:',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final value = preset['value'] as double;
            final label = preset['label'] as String;
            final isSelected = selectedWeight == value;

            return InkWell(
              onTap: () {
                setState(() {
                  selectedWeight = value;
                  _weightController.text = value.toStringAsFixed(0);
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.blue[900]! : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDurationInfo() {
    final duration = _calculateServoDuration(selectedWeight);
    final durationSeconds = (duration / 1000).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.blue[700],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimasi Durasi Servo',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue[900],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$duration ms (~$durationSeconds detik)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSwitch() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status Jadwal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[900],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isEnabled ? 'Aktif' : 'Nonaktif',
                style: TextStyle(
                  fontSize: 12,
                  color: isEnabled ? Colors.green[700] : Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Switch(
            value: isEnabled,
            onChanged: (value) {
              setState(() {
                isEnabled = value;
              });
            },
            activeColor: Colors.green[600],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Simpan Jadwal button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saveSchedule,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: Text(
              widget.isEdit ? 'Simpan Perubahan' : 'Simpan Jadwal',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Batal button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              side: BorderSide(color: Colors.grey[400]!, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Batal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // Delete button (only in edit mode)
        if (widget.isEdit) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _deleteSchedule,
              icon: const Icon(Icons.delete_outline),
              label: const Text(
                'Hapus Jadwal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[700],
                side: BorderSide(color: Colors.red[700]!, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
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

    if (picked != null) {
      setState(() {
        selectedTime = picked;
        _timeController.text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} WIB';
      });
    }
  }

  void _saveSchedule() {
    if (_formKey.currentState!.validate()) {
      // Pastikan widget.schedule tidak null saat edit mode
      final scheduleId = widget.isEdit && widget.schedule != null
          ? widget.schedule!.id
          : 'schedule_temp';

      final schedule = FeedingSchedule(
        id: scheduleId,
        time: _timeController.text,
        weightGrams: selectedWeight,
        enabled: isEnabled,
        status: 'Dijadwalkan',
        isCompleted: false,
      );

      Navigator.pop(context, schedule);
    }
  }

  void _deleteSchedule() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Jadwal'),
        content: const Text('Apakah Anda yakin ingin menghapus jadwal ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, 'delete'); // Return delete signal
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
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