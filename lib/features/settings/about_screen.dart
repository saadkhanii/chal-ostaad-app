// lib/features/settings/about_screen.dart
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/sizes.dart';
import '../../shared/widgets/common_header.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = context.locale.languageCode == 'ur';

    return Scaffold(
      backgroundColor: isDark ? CColors.dark : CColors.lightGrey,
      body: Column(
        children: [
          CommonHeader(
            title: 'drawer.about'.tr(),
            showBackButton: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CSizes.defaultSpace),
              children: [

                // ── App identity card ───────────────────────────────
                Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.all(CSizes.lg),
                  decoration: BoxDecoration(
                    color:        isDark ? CColors.darkContainer : CColors.white,
                    borderRadius: BorderRadius.circular(CSizes.cardRadiusLg),
                  ),
                  child: Column(
                    children: [
                      // Logo
                      Container(
                        padding:    const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [CColors.primary, CColors.secondary],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.handyman_rounded,
                            color: Colors.white, size: 42),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Chal Ostaad',
                        style: TextStyle(
                          fontSize:   isUrdu ? 24 : 22,
                          fontWeight: FontWeight.bold,
                          color:      isDark ? CColors.white : CColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),

                      Text(
                        'drawer.app_version'.tr(),
                        style: TextStyle(
                          fontSize: 13,
                          color:    isDark ? CColors.lightGrey : CColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Chal Ostaad connects skilled workers with clients who '
                            'need quality work done. Post jobs, place bids, chat, '
                            'and get paid — all in one place.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isUrdu ? 14 : 13,
                          height:   1.6,
                          color: isDark ? CColors.lightGrey : CColors.darkerGrey,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── Contact & feedback ──────────────────────────────
                _sectionLabel('CONTACT & FEEDBACK', isDark, isUrdu, context),

                _aboutTile(
                  context,
                  icon:     Icons.email_outlined,
                  title:    'Contact Us',
                  subtitle: 'chalostaad@gmail.com',
                  isDark:   isDark,
                  onTap:    () => _comingSoon(
                      context, 'Opening email: chalostaad@gmail.com'),
                ),

                _aboutTile(
                  context,
                  icon:     Icons.star_outline_rounded,
                  title:    'Rate the App',
                  subtitle: 'Enjoying Chal Ostaad? Leave a review!',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Rate us — coming soon.'),
                ),

                _aboutTile(
                  context,
                  icon:     Icons.share_outlined,
                  title:    'Share the App',
                  subtitle: 'Invite friends and colleagues',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Share — coming soon.'),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),

                // ── Legal ───────────────────────────────────────────
                _sectionLabel('LEGAL', isDark, isUrdu, context),

                _aboutTile(
                  context,
                  icon:     Icons.article_outlined,
                  title:    'Terms of Service',
                  subtitle: 'Read our terms and conditions',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Terms of service coming soon.'),
                ),

                _aboutTile(
                  context,
                  icon:     Icons.policy_outlined,
                  title:    'Privacy Policy',
                  subtitle: 'How we handle your data',
                  isDark:   isDark,
                  onTap:    () =>
                      _comingSoon(context, 'Privacy policy coming soon.'),
                ),

                const SizedBox(height: CSizes.spaceBtwSections),

                // ── Copyright footer ────────────────────────────────
                Center(
                  child: Text(
                    '© 2025 Chal Ostaad. All rights reserved.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? CColors.darkGrey : CColors.lightGrey,
                    ),
                  ),
                ),

                const SizedBox(height: CSizes.spaceBtwItems),
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

  Widget _aboutTile(
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