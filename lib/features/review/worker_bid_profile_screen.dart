// lib/features/review/worker_bid_profile_screen.dart

import 'dart:convert';
import 'package:chal_ostaad/features/review/star_rating_bar.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/review_model.dart';
import '../../core/services/review_service.dart';
import '../../shared/widgets/common_header.dart';
import 'worker_reviews_screen.dart';

class WorkerBidProfileScreen extends StatefulWidget {
  final String workerId;

  const WorkerBidProfileScreen({super.key, required this.workerId});

  @override
  State<WorkerBidProfileScreen> createState() =>
      _WorkerBidProfileScreenState();
}

class _WorkerBidProfileScreenState extends State<WorkerBidProfileScreen> {
  bool   _isLoading    = true;
  String _name         = '';
  String _photoBase64  = '';
  String _experience   = '';
  String _categoryName = '';
  String _phone        = '';
  String _officeCity   = '';
  double _avgRating    = 0.0;
  int    _totalReviews = 0;
  int    _jobsWon      = 0;
  int    _bidsPlaced   = 0;
  List<String>      _skills  = [];
  List<ReviewModel> _reviews = [];

  @override
  void initState() {
    super.initState();
    _loadWorkerData();
  }

  Future<void> _loadWorkerData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();

      if (!doc.exists || !mounted) {
        setState(() => _isLoading = false);
        return;
      }

      final data     = doc.data()!;
      final personal = data['personalInfo'] as Map<String, dynamic>? ?? {};
      final work     = data['workInfo']     as Map<String, dynamic>? ?? {};
      final office   = data['officeInfo']   as Map<String, dynamic>? ?? {};
      final ratings  = data['ratings']      as Map<String, dynamic>? ?? {};

      // Fetch category name
      String categoryName = '';
      final categoryId = work['categoryId'] as String? ?? '';
      if (categoryId.isNotEmpty) {
        try {
          final catDoc = await FirebaseFirestore.instance
              .collection('workCategories')
              .doc(categoryId)
              .get();
          if (catDoc.exists) {
            final c = catDoc.data()!;
            categoryName =
                '${c['icon'] ?? ''} ${c['name'] ?? ''}'.trim();
          }
        } catch (_) {}
      }

      // Fetch bid stats
      int bidsPlaced = 0, jobsWon = 0;
      try {
        final bidsSnap = await FirebaseFirestore.instance
            .collection('bids')
            .where('workerId', isEqualTo: widget.workerId)
            .get();
        bidsPlaced = bidsSnap.docs.length;
        jobsWon    = bidsSnap.docs
            .where((d) => d['status'] == 'accepted')
            .length;
      } catch (_) {}

      // Fetch latest 3 reviews for preview
      final reviews = await ReviewService().getWorkerReviews(widget.workerId);

      if (mounted) {
        setState(() {
          _name         = personal['name']       ?? personal['fullName'] ?? '';
          _photoBase64  = personal['photoBase64'] ?? '';
          _experience   = work['experience']      ?? '';
          _skills       = List<String>.from(work['skills'] ?? []);
          _officeCity   = office['officeCity']    ?? '';
          _categoryName = categoryName;
          _avgRating    = (ratings['average']      as num?)?.toDouble() ?? 0.0;
          _totalReviews = (ratings['totalReviews'] as int?)  ?? 0;
          _bidsPlaced   = bidsPlaced;
          _jobsWon      = jobsWon;
          _reviews      = reviews.take(3).toList();
          _isLoading    = false;
        });
      }
    } catch (e) {
      debugPrint('WorkerBidProfileScreen: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = Localizations.localeOf(context).languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'Worker Profile',
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileHeader(isDark, isUrdu),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildStatsRow(isDark, isUrdu),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  if (_experience.isNotEmpty) ...[
                    _buildSection(
                      context, isDark, isUrdu,
                      icon:  Icons.work_history_outlined,
                      title: 'Experience',
                      child: Text(
                        _experience,
                        style: TextStyle(
                          fontSize: isUrdu ? 14 : 13,
                          color:    isDark
                              ? CColors.textWhite.withOpacity(0.85)
                              : CColors.textPrimary,
                          height:   1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: CSizes.spaceBtwSections),
                  ],
                  if (_skills.isNotEmpty) ...[
                    _buildSection(
                      context, isDark, isUrdu,
                      icon:  Icons.auto_awesome_outlined,
                      title: 'Skills',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _skills
                            .map((s) => _buildSkillChip(s, isDark))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: CSizes.spaceBtwSections),
                  ],
                  _buildReviewsPreview(context, isDark, isUrdu),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile header: photo, name, category, city ────────────────
  Widget _buildProfileHeader(bool isDark, bool isUrdu) {
    ImageProvider? img;
    if (_photoBase64.isNotEmpty) {
      try { img = MemoryImage(base64Decode(_photoBase64)); } catch (_) {}
    }

    return Container(
      padding:    const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : Colors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius:          40,
            backgroundColor: CColors.primary.withOpacity(0.15),
            backgroundImage: img,
            child: img == null
                ? Text(
              _name.isNotEmpty ? _name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize:   28,
                fontWeight: FontWeight.bold,
                color:      CColors.primary,
              ),
            )
                : null,
          ),
          const SizedBox(width: CSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: TextStyle(
                    fontSize:   isUrdu ? 20 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_categoryName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _categoryName,
                    style: TextStyle(
                      color:    CColors.primary,
                      fontSize: isUrdu ? 14 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_officeCity.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: CColors.darkGrey),
                      const SizedBox(width: 2),
                      Text(
                        _officeCity,
                        style: TextStyle(
                          color:    CColors.darkGrey,
                          fontSize: isUrdu ? 13 : 12,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                // Star rating inline
                Row(
                  children: [
                    StarRatingBar(rating: _avgRating, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _totalReviews > 0
                          ? '${_avgRating.toStringAsFixed(1)} ($_totalReviews)'
                          : 'No reviews',
                      style: TextStyle(
                        color:    CColors.darkGrey,
                        fontSize: isUrdu ? 13 : 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row: bids placed, jobs won ──────────────────────────
  Widget _buildStatsRow(bool isDark, bool isUrdu) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Bids Placed', '$_bidsPlaced',
            Icons.gavel_outlined, isDark, isUrdu)),
        const SizedBox(width: CSizes.md),
        Expanded(child: _buildStatCard('Jobs Won', '$_jobsWon',
            Icons.check_circle_outline_rounded, isDark, isUrdu)),
        const SizedBox(width: CSizes.md),
        Expanded(child: _buildStatCard('Rating',
            _totalReviews > 0
                ? _avgRating.toStringAsFixed(1)
                : 'N/A',
            Icons.star_outline_rounded, isDark, isUrdu)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon,
      bool isDark, bool isUrdu) {
    return Container(
      padding:    const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : Colors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: CColors.primary, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize:   isUrdu ? 17 : 16,
              color:      CColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color:    CColors.darkGrey,
              fontSize: isUrdu ? 11 : 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Section wrapper ────────────────────────────────────────────
  Widget _buildSection(
      BuildContext context,
      bool isDark,
      bool isUrdu, {
        required IconData icon,
        required String   title,
        required Widget   child,
      }) {
    return Container(
      padding:    const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : Colors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: CColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   isUrdu ? 16 : 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: CSizes.md),
          child,
        ],
      ),
    );
  }

  Widget _buildSkillChip(String skill, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        CColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: CColors.primary.withOpacity(0.3)),
      ),
      child: Text(
        skill,
        style: const TextStyle(
          color:      CColors.primary,
          fontSize:   12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Reviews preview (last 3) ───────────────────────────────────
  Widget _buildReviewsPreview(
      BuildContext context, bool isDark, bool isUrdu) {
    return Container(
      padding:    const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : Colors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Reviews',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize:   isUrdu ? 16 : 15,
                    ),
                  ),
                ],
              ),
              if (_totalReviews > 3)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WorkerReviewsScreen(
                        workerId:      widget.workerId,
                        workerName:    _name,
                        averageRating: _avgRating,
                        totalReviews:  _totalReviews,
                      ),
                    ),
                  ),
                  child: Text(
                    'See all $_totalReviews',
                    style: const TextStyle(color: CColors.primary),
                  ),
                ),
            ],
          ),

          if (_reviews.isEmpty) ...[
            const SizedBox(height: CSizes.md),
            Center(
              child: Text(
                'No reviews yet',
                style: TextStyle(
                  color:    CColors.darkGrey,
                  fontSize: isUrdu ? 14 : 13,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: CSizes.md),
            ..._reviews.map((r) => _buildMiniReview(r, isDark, isUrdu)),
            if (_totalReviews > 3) ...[
              const SizedBox(height: CSizes.sm),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WorkerReviewsScreen(
                        workerId:      widget.workerId,
                        workerName:    _name,
                        averageRating: _avgRating,
                        totalReviews:  _totalReviews,
                      ),
                    ),
                  ),
                  child: Text(
                    'View all $_totalReviews reviews →',
                    style: const TextStyle(color: CColors.primary),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMiniReview(
      ReviewModel review, bool isDark, bool isUrdu) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius:          14,
                backgroundColor: CColors.primary.withOpacity(0.15),
                child: Text(
                  review.clientName.isNotEmpty
                      ? review.clientName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    color:      CColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize:   12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.clientName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize:   isUrdu ? 13 : 12,
                  ),
                ),
              ),
              StarRatingBar(rating: review.rating, size: 13),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                review.comment,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isUrdu ? 13 : 12,
                  color:    isDark
                      ? CColors.textWhite.withOpacity(0.7)
                      : CColors.darkerGrey,
                ),
              ),
            ),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }
}