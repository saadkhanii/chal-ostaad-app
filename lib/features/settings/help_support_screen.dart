// lib/features/settings/help_support_screen.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/common_header.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'drawer.help_support'.tr(),
            showBackButton: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              children: [

                // ── Contact us banner ───────────────────────────────
                Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.all(CSizes.lg),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [CColors.primary, CColors.secondary],
                    ),
                    borderRadius:
                    BorderRadius.circular(CSizes.cardRadiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.support_agent_rounded,
                          color: Colors.white, size: 32),
                      const SizedBox(height: 10),
                      Text(
                        'We\'re here to help!',
                        style: TextStyle(
                          color:      Colors.white,
                          fontSize:   isUrdu ? 18 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reach out anytime at chalostaad@gmail.com',
                        style: TextStyle(
                          color:    Colors.white.withOpacity(0.9),
                          fontSize: isUrdu ? 14 : 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── CONTACT ────────────────────────────────────────
                _sectionLabel('CONTACT', isDark, isUrdu, context),

                _helpTile(
                  context,
                  icon:     Icons.email_outlined,
                  title:    'Email Support',
                  subtitle: 'chalostaad@gmail.com',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(context,
                      'Opening email: chalostaad@gmail.com'),
                ),

                _helpTile(
                  context,
                  icon:     Icons.bug_report_outlined,
                  title:    'Report a Problem',
                  subtitle: 'Tell us what went wrong',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Problem reporting coming soon.'),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── RESOURCES ──────────────────────────────────────
                _sectionLabel('RESOURCES', isDark, isUrdu, context),

                _helpTile(
                  context,
                  icon:     Icons.quiz_outlined,
                  title:    'FAQs',
                  subtitle: 'Browse frequently asked questions',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(context, 'FAQs coming soon.'),
                ),

                _helpTile(
                  context,
                  icon:     Icons.video_library_outlined,
                  title:    'How to Use the App',
                  subtitle: 'Step-by-step guides and tutorials',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Guides coming soon.'),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── LEGAL ──────────────────────────────────────────
                _sectionLabel('LEGAL', isDark, isUrdu, context),

                _helpTile(
                  context,
                  icon:     Icons.article_outlined,
                  title:    'Terms of Service',
                  subtitle: 'Read our terms and conditions',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Terms of service coming soon.'),
                ),

                _helpTile(
                  context,
                  icon:     Icons.policy_outlined,
                  title:    'Privacy Policy',
                  subtitle: 'How we handle your data',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Privacy policy coming soon.'),
                ),

                _helpTile(
                  context,
                  icon:     Icons.gavel_outlined,
                  title:    'Refund Policy',
                  subtitle: 'Payment and refund guidelines',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Refund policy coming soon.'),
                ),

                const SizedBox(height: CSizes.spaceBtwSections),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, bool isDark, bool isUrdu, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize:      isUrdu ? 14 : 11,
          fontWeight:    FontWeight.bold,
          letterSpacing: 1.2,
          color:         isDark ? CColors.lightGrey : CColors.darkGrey,
        ),
      ),
    );
  }

  Widget _helpTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required bool isDark,
        required VoidCallback onTap,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color:        isDark ? CColors.darkContainer : CColors.white,
        borderRadius: BorderRadius.circular(CSizes.borderRadiusMd),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
        leading: Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:        CColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: CColors.primary, size: 20),
        ),
        title: Text(title,
            style: TextStyle(
              fontSize:   14,
              fontWeight: FontWeight.w600,
              color:      isDark ? CColors.white : CColors.textPrimary,
            )),
        subtitle: Text(subtitle,
            style: TextStyle(
              fontSize: 12,
              color:    isDark ? CColors.lightGrey : CColors.darkGrey,
            )),
        trailing: Icon(Icons.chevron_right_rounded,
            color: isDark ? CColors.darkGrey : CColors.lightGrey, size: 20),
        onTap: onTap,
      ),
    );
  }

  void _comingSoon(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:  Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }
}