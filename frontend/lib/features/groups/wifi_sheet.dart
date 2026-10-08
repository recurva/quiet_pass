import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';

/// Add/edit sheet for the house's Wi-Fi SSID/password. Returns (ssid,
/// password) trimmed, or null if dismissed without confirming — same
/// pure input shape as [showAgreementSheet]/[showCustomNudgeSheet].
Future<(String, String)?> showWifiSheet(
  BuildContext context, {
  String? initialSsid,
  String? initialPassword,
}) {
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WifiSheet(initialSsid: initialSsid, initialPassword: initialPassword),
  );
}

class _WifiSheet extends StatefulWidget {
  const _WifiSheet({this.initialSsid, this.initialPassword});

  final String? initialSsid;
  final String? initialPassword;

  @override
  State<_WifiSheet> createState() => _WifiSheetState();
}

class _WifiSheetState extends State<_WifiSheet> {
  late final _ssidController = TextEditingController(text: widget.initialSsid);
  late final _passwordController = TextEditingController(text: widget.initialPassword);
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.base.w,
        right: Space.base.w,
        top: Space.base.h,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.base.h,
      ),
      child: Container(
        padding: EdgeInsets.all(Space.base.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg.r),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wi-Fi details', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Used to generate the guest QR code. Visible to the whole house.',
              style: context.text.bodySmall,
            ),
            SizedBox(height: Space.lg.h),
            TextField(
              controller: _ssidController,
              autofocus: true,
              maxLength: 100,
              style: context.text.bodyLarge?.copyWith(color: c.ink),
              decoration: _fieldDecoration(context, hint: 'Network name (SSID)'),
            ),
            SizedBox(height: Space.sm.h),
            TextField(
              controller: _passwordController,
              maxLength: 100,
              obscureText: _obscurePassword,
              style: context.text.bodyLarge?.copyWith(color: c.ink),
              decoration: _fieldDecoration(context, hint: 'Password').copyWith(
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: c.ink3,
                    size: 20.r,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: Space.sm.h),
              Text(_error!, style: context.text.bodySmall?.copyWith(color: c.call.solid)),
            ],
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, {required String hint}) {
    final c = context.colors;
    return InputDecoration(
      counterText: '',
      hintText: hint,
      hintStyle: context.text.bodyLarge?.copyWith(color: c.ink3),
      filled: true,
      fillColor: c.surface2,
      contentPadding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md.r),
        borderSide: BorderSide(color: c.line2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md.r),
        borderSide: BorderSide(color: c.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md.r),
        borderSide: BorderSide(color: c.accent),
      ),
    );
  }

  void _submit() {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'Enter the network name.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter the password.');
      return;
    }
    Navigator.of(context).pop((ssid, password));
  }
}
