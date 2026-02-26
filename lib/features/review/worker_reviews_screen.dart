// lib/features/review/worker_reviews_screen.dart
//
// Shows all reviews for a given worker.
// Rating summary is computed LIVE from the stream so it always stays up to date.

import 'package:chal_ostaad/features/review/star_rating_bar.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/review_model.dart';
import '../../core/services/review_service.dart';
import '../../shared/widgets/common_header.dart';

class WorkerReviewsScreen extends StatelessWidget {
  final String workerId;
  final String workerName;

  // Optional fallback values shown before the stream loads
  final double averageRating;
  final int    totalReviews;

  const WorkerReviewsScreen({
    super.key,
    required this.workerId,
    required this.workerName,
    this.averageRating = 0.0,
    this.totalReviews  = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = Localizations.localeOf(context).languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title:          'Reviews',
            showBackButton: true,
            onBackPressed:  () => Navigator.pop(context),
          ),
          Expanded(
            child: StreamBuilder<List<ReviewModel>>(
              stream: ReviewService().workerReviewsStream(workerId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final reviews = snap.data ?? [];

                // ── Compute live stats from the stream ─────────────
                final liveTotal = reviews.length;
                final liveAvg   = liveTotal == 0
                    ? 0.0
                    : reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                    liveTotal;

                return CustomScrollView(
                  slivers: [
                    // ── Summary card (always live) ──────────────────
                    SliverToBoxAdapter(
                      child: _buildSummaryCard(
                        context, isDark, isUrdu,
                        liveAvg:   liveAvg,
                        liveTotal: liveTotal,
                      ),
                    ),

                    if (reviews.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.star_outline_rounded,
                                  size: 64, color: CColors.grey),
                              const SizedBox(height: CSizes.md),
                              Text(
                                'No reviews yet',
                                style: TextStyle(
                                  color:    CColors.darkGrey,
                                  fontSize: isUrdu ? 17 : 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: CSizes.defaultSpace),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) =>
                                _buildReviewCard(reviews[index], isDark, isUrdu),
                            childCount: reviews.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      BuildContext context, bool isDark, bool isUrdu, {
        required double liveAvg,
        required int    liveTotal,
      }) {
    return Container(
      margin:  const EdgeInsets.all(CSizes.defaultSpace),
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color: isDark ? CColors.darkContainer : Colors.white,
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
          // Big number — always from live stream
          Column(
            children: [
              Text(
                liveAvg > 0
                    ? liveAvg.toStringAsFixed(1)
                    : 'N/A',
                style: TextStyle(
                  fontSize:   isUrdu ? 50 : 48,
                  fontWeight: FontWeight.bold,
                  color:      CColors.primary,
                ),
              ),
              StarRatingBar(rating: liveAvg, size: 20),
              const SizedBox(height: 4),
              Text(
                '$liveTotal ${liveTotal == 1 ? 'review' : 'reviews'}',
                style: TextStyle(
                  color:    CColors.darkGrey,
                  fontSize: isUrdu ? 13 : 12,
                ),
              ),
            ],
          ),
          const SizedBox(width: CSizes.lg),
          // Worker name + label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workerName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize:   isUrdu ? 18 : 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  liveAvg >= 4.5
                      ? '🌟 Top Rated Worker'
                      : liveAvg >= 3.5
                      ? '👍 Highly Recommended'
                      : liveAvg > 0
                      ? '⭐ Rated by clients'
                      : 'No ratings yet',
                  style: TextStyle(
                    color:    CColors.darkGrey,
                    fontSize: isUrdu ? 13 : 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(
      ReviewModel review, bool isDark, bool isUrdu) {
    return Card(
      margin:    const EdgeInsets.only(bottom: CSizes.md),
      elevation: 1.5,
      shape:     RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      child: Padding(
        padding: const EdgeInsets.all(CSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client name + date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius:          18,
                      backgroundColor: CColors.primary.withOpacity(0.15),
                      child: Text(
                        review.clientName.isNotEmpty
                            ? review.clientName[0].toUpperCase()
                            : 'C',
                        style: const TextStyle(
                          color:      CColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      review.clientName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize:   isUrdu ? 15 : 14,
                      ),
                    ),
                  ],
                ),
                Text(
                  timeago.format(review.createdAt.toDate()),
                  style: TextStyle(
                    color:    CColors.darkGrey,
                    fontSize: isUrdu ? 12 : 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Stars
            StarRatingBar(rating: review.rating, size: 16),

            // Comment
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review.comment,
                style: TextStyle(
                  fontSize: isUrdu ? 14 : 13,
                  color:    isDark
                      ? CColors.textWhite.withOpacity(0.85)
                      : CColors.textPrimary,
                  height:   1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}