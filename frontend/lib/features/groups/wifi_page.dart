import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';
import 'wifi_qr.dart';
import 'wifi_sheet.dart';

/// Wi-Fi + house-rules guest portal: a QR a guest scans with their own
/// camera to join the network, plus the house's pinned rules shown below
/// it (the agreements board, read-only here — not a second copy of the
/// data). Admin-only to set the Wi-Fi details; any member can open this
/// screen and show the QR to a guest.
class WifiPage extends ConsumerWidget {
  const WifiPage({super.key, required this.groupId, required this.groupName, required this.isAdmin});

  final String groupId;
  final String groupName;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    ref.watch(groupWifiLiveRefreshProvider(groupId));
    ref.watch(groupAgreementsLiveRefreshProvider(groupId));
    final wifiAsync = ref.watch(groupWifiCredentialsProvider(groupId));
    final agreementsAsync = ref.watch(groupAgreementsProvider(groupId));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              SizedBox(height: Space.lg.h),
              _scanDisclaimerBanner(context),
              SizedBox(height: Space.base.h),
              Text(
                'WI-FI',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: Space.sm.h),
              wifiAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(
                    friendlyErrorMessage(error),
                    style: context.text.bodySmall?.copyWith(color: c.ink3),
                  ),
                ),
                data: (wifi) => _wifiCard(context, ref, wifi),
              ),
              SizedBox(height: Space.base.h),
              Text(
                'HOUSE RULES',
                style: context.text.labelLarge?.copyWith(
                  color: c.ink3,
                  fontSize: 11.sp,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: Space.sm.h),
              agreementsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(
                    friendlyErrorMessage(error),
                    style: context.text.bodySmall?.copyWith(color: c.ink3),
                  ),
                ),
                data: (agreements) {
                  if (agreements.isEmpty) {
                    return Text('Nothing pinned yet.', style: context.text.bodySmall?.copyWith(color: c.ink3));
                  }
                  return Column(
                    children: [
                      for (final agreement in agreements)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.sm.h),
                          child: _RuleCard(agreement: agreement),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
          ),
          icon: Icon(Icons.arrow_back, color: c.ink2, size: 20.r),
        ),
        SizedBox(width: Space.md.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Guest portal', style: context.text.titleLarge),
              SizedBox(height: 2.h),
              Text(groupName, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scanDisclaimerBanner(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.md.w),
      decoration: BoxDecoration(
        color: c.accentTint,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.accentRing),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18.r, color: c.accent),
          SizedBox(width: Space.sm.w),
          Expanded(
            child: Text(
              "This app doesn't connect your guest to Wi-Fi automatically. "
              'Have them scan the QR below with their own phone\'s camera — '
              'it\'ll prompt them to join.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wifiCard(BuildContext context, WidgetRef ref, WifiCredentials? wifi) {
    final c = context.colors;
    if (wifi == null) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(Space.base.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md.r),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAdmin
                  ? 'No Wi-Fi details set yet.'
                  : 'No Wi-Fi details set yet. Ask a house admin to add them.',
              style: context.text.bodyMedium?.copyWith(color: c.ink3),
            ),
            if (isAdmin) ...[
              SizedBox(height: Space.md.h),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _editWifi(context, ref),
                  child: const Text('Add Wi-Fi details'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(Space.md.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Radii.sm.r),
            ),
            child: QrImageView(
              data: buildWifiQrPayload(ssid: wifi.ssid, password: wifi.password),
              size: 200.r,
              backgroundColor: Colors.white,
            ),
          ),
          SizedBox(height: Space.md.h),
          Text(wifi.ssid, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 2.h),
          Text('Scan to join', style: context.text.bodySmall?.copyWith(color: c.ink3)),
          if (isAdmin) ...[
            SizedBox(height: Space.md.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _editWifi(context, ref, currentSsid: wifi.ssid),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink2,
                  side: BorderSide(color: c.line2),
                ),
                child: const Text('Edit Wi-Fi details'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editWifi(BuildContext context, WidgetRef ref, {String? currentSsid}) async {
    final result = await showWifiSheet(context, initialSsid: currentSsid);
    if (result == null || !context.mounted) return;
    final (ssid, password) = result;

    try {
      await ref.read(groupsRepositoryProvider).setWifiCredentials(groupId, ssid, password);
      ref.invalidate(groupWifiCredentialsProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.agreement});

  final AppAgreement agreement;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(agreement.title, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: Space.xs.h),
          Text(agreement.content, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}
