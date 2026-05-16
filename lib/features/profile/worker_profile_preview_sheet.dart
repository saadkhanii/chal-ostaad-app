// lib/features/profile/worker_profile_preview_sheet.dart
import 'dart:convert';

import 'package:chal_ostaad/features/profile/worker_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';

class WorkerProfilePreviewSheet extends StatelessWidget {
  final String workerId;

  const WorkerProfilePreviewSheet({
    super.key,
    required this.workerId,
  });

  static Future<void> show(BuildContext context, {required String workerId}) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => WorkerProfilePreviewSheet(workerId: workerId),
      isScrollControlled: true,
    );
  }

  Future<String> _getCategoryName(String categoryId) async {
    if (categoryId.isEmpty) return '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workCategories')
          .doc(categoryId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Try common field names — adjust to whatever your schema uses
        final icon = data['icon'] as String? ?? '';
        final name = data['name'] as String? ?? '';
        final combined = '$icon $name'.trim();
        return combined.isNotEmpty ? combined : categoryId;
      }
      return categoryId; // fallback to raw ID if doc not found
    } catch (_) {
      return categoryId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('workers').doc(workerId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 200,
            padding: const EdgeInsets.all(CSizes.lg),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Container(
            height: 200,
            padding: const EdgeInsets.all(CSizes.lg),
            child: const Center(child: Text('Worker not found')),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final personal = data['personalInfo'] as Map<String, dynamic>? ?? {};
        final work = data['workInfo'] as Map<String, dynamic>? ?? {};
        final ratings = data['ratings'] as Map<String, dynamic>? ?? {};
        final verification = data['verification'] as Map<String, dynamic>? ?? {};

        final name = personal['fullName'] ?? personal['name'] ?? 'Worker';
        final photoBase64 = personal['photoBase64'] as String? ?? '';
        final categoryId = work['categoryId'] as String? ?? '';
        final experience = work['experience'] as String? ?? '';
        final skills = List<String>.from(work['skills'] ?? []);
        final avgRating = (ratings['average'] as num?)?.toDouble() ?? 0.0;
        final totalReviews = ratings['totalReviews'] as int? ?? 0;
        final verificationStatus = verification['status'] as String? ?? 'pending';
        final isVerified = verificationStatus == 'verified';

        return Container(
          padding: const EdgeInsets.all(CSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: photo + name ─────────────────────────────
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: CColors.secondary,
                    backgroundImage: photoBase64.isNotEmpty
                        ? MemoryImage(base64Decode(photoBase64))
                        : null,
                    child: photoBase64.isEmpty
                        ? Text(
                      name.split(' ').map((w) => w[0]).take(2).join().toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                        : null,
                  ),
                  const SizedBox(width: CSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            if (isVerified)
                              const Icon(Icons.verified, color: CColors.success, size: 20),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (avgRating > 0)
                          Row(
                            children: [
                              ...List.generate(5, (i) => Icon(
                                i < avgRating.floor() ? Icons.star : Icons.star_border,
                                color: CColors.warning,
                                size: 14,
                              )),
                              const SizedBox(width: 4),
                              Text(
                                '$avgRating ($totalReviews reviews)',
                                style: TextStyle(fontSize: 12, color: CColors.darkGrey),
                              ),
                            ],
                          ),
                        // FIX 4: Fetch and display the human-readable category name
                        if (categoryId.isNotEmpty)
                          FutureBuilder<String>(
                            future: _getCategoryName(categoryId),
                            builder: (context, catSnapshot) {
                              final catName = catSnapshot.data ?? '';
                              if (catName.isEmpty) return const SizedBox.shrink();
                              return Text(
                                catName,
                                style: TextStyle(fontSize: 13, color: CColors.darkGrey),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.md),

              // ── Experience & Skills ──────────────────────────────
              if (experience.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: CSizes.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.timeline_outlined, size: 16, color: CColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Experience: $experience',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? CColors.textWhite : CColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (skills.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: skills
                      .map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: CColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(fontSize: 11, color: CColors.primary),
                    ),
                  ))
                      .toList(),
                ),
              const SizedBox(height: CSizes.md),

              // ── View Full Profile button ─────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // FIX 2: Pass the correct workerId so we open THAT worker's
                    // profile, not the currently logged-in user's profile.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkerProfileScreen(
                          showAppBar: true,
                          workerId: workerId, // ← the worker whose card was tapped
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CSizes.borderRadiusLg),
                    ),
                  ),
                  child: const Text('View Full Profile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}