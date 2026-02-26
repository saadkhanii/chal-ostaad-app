// lib/features/review/submit_review_dialog.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';

/// A modal bottom sheet that lets the client rate (1–5 stars) and
/// optionally leave a comment. Call via [SubmitReviewDialog.show].
class SubmitReviewDialog extends StatefulWidget {
  final String workerName;
  final void Function(double rating, String comment) onSubmit;

  const SubmitReviewDialog({
    super.key,
    required this.workerName,
    required this.onSubmit,
  });

  // ── Convenience launcher ──────────────────────────────────────
  static Future<void> show(
      BuildContext context, {
        required String workerName,
        required void Function(double rating, String comment) onSubmit,
      }) {
    return showModalBottomSheet(
      context:       context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => SubmitReviewDialog(
        workerName: workerName,
        onSubmit:   onSubmit,
      ),
    );
  }

  @override
  State<SubmitReviewDialog> createState() => _SubmitReviewDialogState();
}

class _SubmitReviewDialogState extends State<SubmitReviewDialog> {
  double _rating  = 0;
  final  _commentCtrl = TextEditingController();
  bool   _isSubmitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final isUrdu   = Localizations.localeOf(context).languageCode == 'ur';
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
          CSizes.defaultSpace, 24,
          CSizes.defaultSpace, 24 + bottomPad),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Rate your experience',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.bold,
              fontSize:   isUrdu ? 22 : 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was working with ${widget.workerName}?',
            style: TextStyle(
              color:    CColors.darkGrey,
              fontSize: isUrdu ? 14 : 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Star rating row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starValue = i + 1.0;
              return GestureDetector(
                onTap: () => setState(() => _rating = starValue),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    _rating >= starValue
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size:  42,
                    color: _rating >= starValue
                        ? Colors.amber
                        : CColors.darkGrey,
                  ),
                ),
              );
            }),
          ),

          // Rating label
          const SizedBox(height: 8),
          Text(
            _ratingLabel(_rating),
            style: TextStyle(
              color:      CColors.primary,
              fontWeight: FontWeight.w600,
              fontSize:   isUrdu ? 15 : 14,
            ),
          ),
          const SizedBox(height: 20),

          // Comment field
          TextField(
            controller:  _commentCtrl,
            maxLines:    3,
            maxLength:   300,
            decoration: InputDecoration(
              hintText:    'Add a comment (optional)',
              hintStyle:   TextStyle(color: CColors.darkGrey, fontSize: 13),
              filled:      true,
              fillColor:   isDark ? CColors.dark : CColors.lightGrey,
              border:      OutlineInputBorder(
                borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
                borderSide:   BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_rating == 0 || _isSubmitting)
                  ? null
                  : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: CColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: CColors.primary.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CSizes.borderRadiusLg)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : Text(
                'Submit Review',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   isUrdu ? 17 : 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_rating == 0) return;
    setState(() => _isSubmitting = true);
    widget.onSubmit(_rating, _commentCtrl.text.trim());
    Navigator.pop(context);
  }

  String _ratingLabel(double r) {
    if (r == 0) return 'Tap a star to rate';
    if (r <= 1) return '😞  Poor';
    if (r <= 2) return '😕  Fair';
    if (r <= 3) return '😐  Good';
    if (r <= 4) return '😊  Very Good';
    return '🌟  Excellent!';
  }
}