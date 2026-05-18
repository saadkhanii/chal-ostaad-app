// lib/features/shared/widgets/propose_new_time_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';

class ProposeNewTimeDialog extends StatefulWidget {
  final String title;
  final String hint;
  final Future<void> Function(DateTime selectedTime) onPropose;

  const ProposeNewTimeDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.onPropose,
  });

  static Future<void> show(
      BuildContext context, {
        required String title,
        required String hint,
        required Future<void> Function(DateTime) onPropose,
      }) {
    return showDialog(
      context: context,
      builder: (_) => ProposeNewTimeDialog(
        title: title,
        hint: hint,
        onPropose: onPropose,
      ),
    );
  }

  @override
  State<ProposeNewTimeDialog> createState() => _ProposeNewTimeDialogState();
}

class _ProposeNewTimeDialogState extends State<ProposeNewTimeDialog> {
  DateTime? _selectedDateTime;
  bool _isLoading = false;

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (chosen.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a future date and time.')),
      );
      return;
    }
    setState(() => _selectedDateTime = chosen);
  }

  Future<void> _submit() async {
    if (_selectedDateTime == null) return;
    setState(() => _isLoading = true);
    try {
      await widget.onPropose(_selectedDateTime!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: CColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.hint),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickDateTime,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: CColors.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, color: CColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedDateTime == null
                          ? 'Tap to select date and time'
                          : DateFormat('d MMM yyyy, hh:mm a').format(_selectedDateTime!),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedDateTime == null || _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: CColors.primary),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Propose'),
        ),
      ],
    );
  }
}