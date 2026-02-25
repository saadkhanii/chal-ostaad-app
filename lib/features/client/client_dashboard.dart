// lib/features/client/client_dashboard.dart

import 'package:chal_ostaad/features/client/client_job_details_screen.dart';
import 'package:chal_ostaad/features/client/post_job_screen.dart';
import 'package:chal_ostaad/features/notifications/notifications_screen.dart';
import 'package:chal_ostaad/features/chat/client_chat_inbox_screen.dart';
import 'package:chal_ostaad/features/client/my_posted_jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../core/models/job_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/bid_service.dart';
import '../../core/services/job_service.dart';
import '../../shared/widgets/dashboard_drawer.dart';
import '../../shared/widgets/curved_nav_bar.dart';
import '../profile/client_profile_screen.dart';
import 'client_dashboard_header.dart';

final clientLoadingProvider = StateProvider<bool>((ref) => true);
final clientPageIndexProvider = StateProvider<int>((ref) => 2);

class ClientDashboard extends ConsumerStatefulWidget {
  const ClientDashboard({super.key});

  @override
  ConsumerState<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends ConsumerState<ClientDashboard> with TickerProviderStateMixin {
  String _userName = '';
  String _clientId = '';
  String _clientEmail = '';
  String _photoBase64 = '';

  // Motivational quotes based on time of day — populated in initState after context is ready
  List<String> _morningQuotes = [];
  List<String> _afternoonQuotes = [];
  List<String> _eveningQuotes = [];

  final ScrollController _myPostedJobsScrollController = ScrollController();
  final ScrollController _postJobScrollController = ScrollController();
  final ScrollController _homeScrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _profileScrollController = ScrollController();

  final JobService _jobService = JobService();
  final BidService _bidService = BidService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Translations require a valid context — initialize them here, after the widget is mounted
      setState(() {
        _userName = 'dashboard.client'.tr();
        _morningQuotes = [
          'quote.morning_1'.tr(),
          'quote.morning_2'.tr(),
          'quote.morning_3'.tr(),
        ];
        _afternoonQuotes = [
          'quote.afternoon_1'.tr(),
          'quote.afternoon_2'.tr(),
          'quote.afternoon_3'.tr(),
        ];
        _eveningQuotes = [
          'quote.evening_1'.tr(),
          'quote.evening_2'.tr(),
          'quote.evening_3'.tr(),
        ];
      });
      _loadUserData();
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _myPostedJobsScrollController.dispose();
    _postJobScrollController.dispose();
    _homeScrollController.dispose();
    _chatScrollController.dispose();
    _profileScrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getMotivationalQuote() {
    final hour = DateTime.now().hour;
    final random = DateTime.now().millisecond % 3;

    if (hour < 12) return _morningQuotes.isNotEmpty ? _morningQuotes[random] : '';
    if (hour < 17) return _afternoonQuotes.isNotEmpty ? _afternoonQuotes[random] : '';
    return _eveningQuotes.isNotEmpty ? _eveningQuotes[random] : '';
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');
      String? userName = prefs.getString('user_name');
      String? userEmail = prefs.getString('user_email');

      if (userUid != null) {
        try {
          final userDoc = await _firestore.collection('users').doc(userUid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data()!;
            final fetchedName = data['fullName'] ?? data['name'] ?? data['userName'] ?? userName ?? 'dashboard.client'.tr();
            final fetchedEmail = data['email'] ?? userEmail ?? '';
            userName = fetchedName;
            userEmail = fetchedEmail;
            await prefs.setString('user_name', fetchedName);
            await prefs.setString('user_email', fetchedEmail);
          }
        } catch (e) {
          debugPrint('Error fetching user data: $e');
        }

        String photoBase64 = '';
        try {
          final clientDoc = await _firestore
              .collection('clients')
              .doc(userUid)
              .get();
          if (clientDoc.exists) {
            final info = clientDoc.data()?['personalInfo'] as Map<String, dynamic>? ?? {};
            photoBase64 = info['photoBase64'] ?? '';
          }
        } catch (e) {
          debugPrint('Error fetching photoBase64: $e');
        }

        if (mounted) {
          setState(() {
            _clientId    = userUid;
            _userName    = userName ?? 'dashboard.client'.tr();
            _clientEmail = userEmail ?? '';
            _photoBase64 = photoBase64;
          });
          ref.read(clientLoadingProvider.notifier).state = false;
        }
      } else {
        if (mounted) ref.read(clientLoadingProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('Error loading client data: $e');
      if (mounted) ref.read(clientLoadingProvider.notifier).state = false;
    }
  }

  void _showJobDetails(JobModel job) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ClientJobDetailsScreen(job: job)));
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return 'Rs 0';
    if (amount >= 10000000) return 'Rs ${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return 'Rs ${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return 'Rs ${(amount / 1000).toStringAsFixed(1)}k';
    return 'Rs ${amount.toStringAsFixed(0)}';
  }

  // ============== ENHANCED UI COMPONENTS ==============

  Widget _buildWelcomeSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CColors.primary,
            CColors.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(
            color: CColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_getGreeting()},',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: CColors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  _userName.split(' ').first,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: CColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isUrdu ? 26 : 24,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: CColors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.format_quote, size: 14, color: CColors.white.withOpacity(0.8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _getMotivationalQuote(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: CColors.white,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CColors.white.withOpacity(0.2),
              border: Border.all(color: CColors.white, width: 2),
            ),
            child: Icon(Icons.emoji_events, color: CColors.white, size: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.add_circle,
                  label: 'Post Job',
                  color: CColors.success,
                  onTap: () => ref.read(clientPageIndexProvider.notifier).state = 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.work,
                  label: 'My Jobs',
                  color: CColors.info,
                  onTap: () => ref.read(clientPageIndexProvider.notifier).state = 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.chat,
                  label: 'Messages',
                  color: CColors.warning,
                  onTap: () => ref.read(clientPageIndexProvider.notifier).state = 3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? CColors.darkContainer : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchClientStats(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final stats = snapshot.data ?? {'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0, 'totalSpent': 0.0};

        // Calculate trends (mock data - replace with real trend calculation)
        final trends = {'postedJobs': '+12%', 'activeJobs': '+5%', 'completedJobs': '+8%', 'totalSpent': '+15%'};

        final items = [
          {
            'label': 'dashboard.posted_jobs'.tr(),
            'value': isLoading ? '...' : '${stats['postedJobs']}',
            'trend': trends['postedJobs'],
            'icon': Icons.work_outline,
            'color': CColors.primary,
          },
          {
            'label': 'dashboard.active_jobs'.tr(),
            'value': isLoading ? '...' : '${stats['activeJobs']}',
            'trend': trends['activeJobs'],
            'icon': Icons.work,
            'color': CColors.warning,
          },
          {
            'label': 'dashboard.completed_jobs'.tr(),
            'value': isLoading ? '...' : '${stats['completedJobs']}',
            'trend': trends['completedJobs'],
            'icon': Icons.check_circle,
            'color': CColors.success,
          },
          {
            'label': 'dashboard.total_spent'.tr(),
            'value': isLoading ? '...' : _formatCurrency(stats['totalSpent']),
            'trend': trends['totalSpent'],
            'icon': Icons.attach_money,
            'color': CColors.info,
          },
        ];

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _buildEnhancedStatCard(
              context,
              label: items[index]['label'] as String,
              value: items[index]['value'] as String,
              trend: items[index]['trend'] as String,
              icon: items[index]['icon'] as IconData,
              color: items[index]['color'] as Color,
            );
          },
        );
      },
    );
  }

  Widget _buildEnhancedStatCard(BuildContext context, {
    required String label,
    required String value,
    required String trend,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? CColors.darkContainer : CColors.white,
            isDark ? CColors.darkContainer.withOpacity(0.8) : CColors.white.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: trend.startsWith('+') ? CColors.success.withOpacity(0.1) : CColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    color: trend.startsWith('+') ? CColors.success : CColors.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: isUrdu ? 24 : 22,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobDistributionChart(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchJobDistribution(),
      builder: (context, snapshot) {
        final hasData = snapshot.hasData && snapshot.data != null;
        final openJobs = (snapshot.data?['open'] as num?)?.toDouble() ?? 0;
        final inProgressJobs = (snapshot.data?['inProgress'] as num?)?.toDouble() ?? 0;
        final completedJobs = (snapshot.data?['completed'] as num?)?.toDouble() ?? 0;
        final total = openJobs + inProgressJobs + completedJobs;

        if (total == 0) {
          return _buildEmptyChart(context);
        }

        return Container(
          height: 160,
          padding: const EdgeInsets.all(CSizes.md),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? CColors.darkContainer
                : CColors.white,
            borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: openJobs,
                        color: CColors.primary,
                        title: '${((openJobs/total)*100).toStringAsFixed(0)}%',
                        radius: 40,
                        titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      PieChartSectionData(
                        value: inProgressJobs,
                        color: CColors.warning,
                        title: '${((inProgressJobs/total)*100).toStringAsFixed(0)}%',
                        radius: 40,
                        titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      PieChartSectionData(
                        value: completedJobs,
                        color: CColors.success,
                        title: '${((completedJobs/total)*100).toStringAsFixed(0)}%',
                        radius: 40,
                        titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                    sectionsSpace: 2,
                    centerSpaceRadius: 30,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendItem(context, 'Open', openJobs.toInt(), CColors.primary),
                    const SizedBox(height: 8),
                    _buildLegendItem(context, 'In Progress', inProgressJobs.toInt(), CColors.warning),
                    const SizedBox(height: 8),
                    _buildLegendItem(context, 'Completed', completedJobs.toInt(), CColors.success),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ($count)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildEmptyChart(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer
            : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 40, color: CColors.grey),
            const SizedBox(height: 8),
            Text(
              'No job data yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchJobDistribution() async {
    if (_clientId.isEmpty) return {'open': 0, 'inProgress': 0, 'completed': 0};

    try {
      final jobsSnapshot = await _firestore
          .collection('jobs')
          .where('clientId', isEqualTo: _clientId)
          .get();

      final jobs = jobsSnapshot.docs;

      return {
        'open': jobs.where((doc) => doc['status'] == 'open').length,
        'inProgress': jobs.where((doc) => doc['status'] == 'in-progress').length,
        'completed': jobs.where((doc) => doc['status'] == 'completed').length,
      };
    } catch (e) {
      debugPrint('Error fetching job distribution: $e');
      return {'open': 0, 'inProgress': 0, 'completed': 0};
    }
  }

  Widget _buildRecentActivity() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: CSizes.sm),
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('jobs')
                .where('clientId', isEqualTo: _clientId)
                .orderBy('createdAt', descending: true)
                .limit(5)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyActivity();
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final job = JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                  return _buildActivityItem(job);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(JobModel job) {
    IconData icon;
    Color color;
    String action;

    switch (job.status) {
      case 'open':
        icon = Icons.post_add;
        color = CColors.primary;
        action = 'posted a new job';
        break;
      case 'in-progress':
        icon = Icons.autorenew;
        color = CColors.warning;
        action = 'job in progress';
        break;
      case 'completed':
        icon = Icons.check_circle;
        color = CColors.success;
        action = 'completed a job';
        break;
      default:
        icon = Icons.fiber_manual_record;
        color = CColors.grey;
        action = 'updated job';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer
            : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$action • ${timeago.format(job.createdAt.toDate())}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CColors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyActivity() {
    return Container(
      padding: const EdgeInsets.all(CSizes.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? CColors.darkContainer
            : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.history, size: 40, color: CColors.grey),
            const SizedBox(height: 8),
            Text(
              'No recent activity',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested for you',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CSizes.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSuggestionCard(
                  context,
                  icon: Icons.rate_review,
                  title: 'Review Workers',
                  subtitle: 'Help others by reviewing workers',
                  color: CColors.primary,
                ),
                const SizedBox(width: 12),
                _buildSuggestionCard(
                  context,
                  icon: Icons.trending_up,
                  title: 'Boost Your Job',
                  subtitle: 'Get more applicants',
                  color: CColors.warning,
                ),
                const SizedBox(width: 12),
                _buildSuggestionCard(
                  context,
                  icon: Icons.people,
                  title: 'Find Top Workers',
                  subtitle: 'Based on your preferences',
                  color: CColors.success,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(CSizes.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Try now →',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchClientStats() async {
    if (_clientId.isEmpty) return {'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0, 'totalSpent': 0.0};
    try {
      final jobsSnapshot = await _firestore.collection('jobs').where('clientId', isEqualTo: _clientId).get();
      final jobs = jobsSnapshot.docs;
      final completedJobIds = jobs.where((doc) => doc['status'] == 'completed').map((doc) => doc.id).toList();
      double totalSpent = 0.0;
      if (completedJobIds.isNotEmpty) {
        final bidsSnapshot = await _firestore.collection('bids')
            .where('jobId', whereIn: completedJobIds).where('status', isEqualTo: 'accepted').get();
        for (var bid in bidsSnapshot.docs) {
          final amount = bid['amount'];
          if (amount is num) totalSpent += amount.toDouble();
        }
      }
      return {
        'postedJobs': jobs.length,
        'activeJobs': jobs.where((doc) => doc['status'] == 'in-progress').length,
        'completedJobs': jobs.where((doc) => doc['status'] == 'completed').length,
        'totalSpent': totalSpent,
      };
    } catch (e) {
      debugPrint('Error fetching client stats: $e');
      return {'postedJobs': 0, 'activeJobs': 0, 'completedJobs': 0, 'totalSpent': 0.0};
    }
  }

  Widget _buildJobFeed({int? limit}) {
    if (_clientId.isEmpty) return _buildEmptyState('job.login_to_view'.tr());
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('jobs').where('clientId', isEqualTo: _clientId)
          .orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingJobs();
        if (snapshot.hasError) return _buildEmptyState('${'errors.load_jobs_failed'.tr()}: ${snapshot.error}');
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState('job.no_jobs_found'.tr());
        int itemCount = snapshot.data!.docs.length;
        if (limit != null && limit < itemCount) itemCount = limit;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            return _buildJobCard(JobModel.fromMap(doc.data() as Map<String, dynamic>, doc.id));
          },
        );
      },
    );
  }

  Widget _buildJobCard(JobModel job) {
    final isUrdu = context.locale.languageCode == 'ur';
    Color statusColor;
    String statusText;
    switch (job.status) {
      case 'open': statusColor = CColors.success; statusText = 'job.status_open'.tr(); break;
      case 'in-progress': statusColor = CColors.warning; statusText = 'job.status_in_progress'.tr(); break;
      case 'completed': statusColor = CColors.info; statusText = 'job.status_completed'.tr(); break;
      case 'cancelled': statusColor = CColors.error; statusText = 'job.status_cancelled'.tr(); break;
      default: statusColor = CColors.grey; statusText = job.status;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: CSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CSizes.cardRadiusMd)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showJobDetails(job),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(CSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(job.title,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold, fontSize: isUrdu ? 18 : 16,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(statusText,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: statusColor, fontWeight: FontWeight.bold, fontSize: isUrdu ? 12 : 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CSizes.sm),
              Text(job.description,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: isUrdu ? 16 : 14),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: CSizes.md),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: CColors.darkGrey),
                  const SizedBox(width: 4),
                  Text(timeago.format(job.createdAt.toDate()),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: isUrdu ? 14 : 12),
                  ),
                  const Spacer(),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('bids').where('jobId', isEqualTo: job.id).snapshots(),
                    builder: (context, bidSnapshot) {
                      final bidCount = bidSnapshot.data?.docs.length ?? 0;
                      return Row(
                        children: [
                          Icon(Icons.gavel, size: 16, color: CColors.primary),
                          const SizedBox(width: 4),
                          Text('${'bid.total_bids'.tr()}: $bidCount',
                            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                              color: CColors.primary, fontWeight: FontWeight.bold, fontSize: isUrdu ? 14 : 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingJobs() {
    final isUrdu = context.locale.languageCode == 'ur';
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: CColors.primary),
            const SizedBox(height: CSizes.md),
            Text('common.loading_jobs'.tr(),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: isUrdu ? 16 : 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? CColors.darkContainer : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.work_outline, size: 48, color: CColors.grey),
            const SizedBox(height: CSizes.md),
            Text(message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: CColors.textSecondary, fontSize: isUrdu ? 16 : 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============== PAGES ==============

  List<Widget> _getPages() {
    return [
      MyPostedJobsScreen(scrollController: _myPostedJobsScrollController),
      PostJobScreen(
        showAppBar: false,
        onJobPosted: () {
          ref.read(clientPageIndexProvider.notifier).state = 2;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('job.job_posted'.tr()),
            backgroundColor: CColors.success,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ));
        },
      ),
      _buildHomePage(),
      ChatInboxScreen(scrollController: _chatScrollController, showAppBar: false),
      ClientProfileScreen(showAppBar: false),
    ];
  }

  Widget _buildHomePage() {
    final isLoading = ref.watch(clientLoadingProvider);
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadUserData,
      child: CustomScrollView(
        controller: _homeScrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  ClientDashboardHeader(
                    userName: _userName,
                    photoUrl: _photoBase64,
                    onNotificationTap: () => Navigator.pushNamed(
                        context, AppRoutes.notifications),
                  ),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildWelcomeSection(context),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  _buildQuickActions(context),
                  const SizedBox(height: CSizes.spaceBtwSections),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
                    child: _buildOpportunityCard(context),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: CSizes.defaultSpace),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'dashboard.project_overview'.tr(), showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildStatsGrid(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'Job Distribution', showAction: false),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobDistributionChart(context),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildRecentActivity(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSuggestedActions(),
                const SizedBox(height: CSizes.spaceBtwSections),
                _buildSectionHeader(context, 'bid.recent_jobs'.tr(),
                  actionText: 'common.view_all'.tr(),
                  onAction: () => ref.read(clientPageIndexProvider.notifier).state = 0,
                ),
                const SizedBox(height: CSizes.spaceBtwItems),
                _buildJobFeed(limit: 3),
                const SizedBox(height: CSizes.spaceBtwSections * 2),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpportunityCard(BuildContext context) {
    final isUrdu = context.locale.languageCode == 'ur';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CSizes.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CColors.primary.withOpacity(0.95), CColors.secondary.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
        boxShadow: [
          BoxShadow(color: CColors.primary.withOpacity(0.4), blurRadius: 25, offset: const Offset(0, 10)),
          BoxShadow(color: CColors.secondary.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: CColors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: CColors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.business_center_rounded, size: 16, color: CColors.white),
                const SizedBox(width: 8),
                Text(
                  'dashboard.job_platform'.tr(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: CColors.white, fontWeight: FontWeight.w800,
                    fontSize: isUrdu ? 12 : 11, letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'dashboard.post_job'.tr(),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: CColors.white, fontWeight: FontWeight.w900,
              fontSize: isUrdu ? 26 : 24, height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dashboard.find_workers'.tr(),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CColors.white.withOpacity(0.95), height: 1.6, fontSize: isUrdu ? 16 : 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CSizes.lg),
          ElevatedButton(
            onPressed: () => ref.read(clientPageIndexProvider.notifier).state = 1,
            style: ElevatedButton.styleFrom(
              backgroundColor: CColors.white,
              foregroundColor: CColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('dashboard.post_now'.tr(), style: TextStyle(fontSize: isUrdu ? 16 : 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {
    String? actionText, VoidCallback? onAction, bool showAction = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w900,
            color: isDark ? CColors.textWhite : CColors.textPrimary,
            fontSize: isUrdu ? 24 : 22,
            letterSpacing: -0.5,
          ),
        ),
        if (showAction && actionText != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                actionText,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: CColors.primary, fontWeight: FontWeight.w700, fontSize: isUrdu ? 16 : 14,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';
    final currentPageIndex = ref.watch(clientPageIndexProvider);

    ScrollController activeController;
    switch (currentPageIndex) {
      case 0: activeController = _myPostedJobsScrollController; break;
      case 1: activeController = _postJobScrollController; break;
      case 2: activeController = _homeScrollController; break;
      case 3: activeController = _chatScrollController; break;
      case 4: activeController = _profileScrollController; break;
      default: activeController = _homeScrollController;
    }

    return Scaffold(
      endDrawer: !isUrdu ? const DashboardDrawer() : null,
      drawer: isUrdu ? const DashboardDrawer() : null,
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: IndexedStack(index: currentPageIndex, children: _getPages()),
      bottomNavigationBar: CurvedNavBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          ref.read(clientPageIndexProvider.notifier).state = index;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            switch (index) {
              case 0: if (_myPostedJobsScrollController.hasClients) _myPostedJobsScrollController.jumpTo(0); break;
              case 1: if (_postJobScrollController.hasClients) _postJobScrollController.jumpTo(0); break;
              case 2: if (_homeScrollController.hasClients) _homeScrollController.jumpTo(0); break;
              case 3: if (_chatScrollController.hasClients) _chatScrollController.jumpTo(0); break;
              case 4: if (_profileScrollController.hasClients) _profileScrollController.jumpTo(0); break;
            }
          });
        },
        userRole: 'client',
        scrollController: activeController,
      ),
    );
  }
}