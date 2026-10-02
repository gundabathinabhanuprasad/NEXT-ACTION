import 'package:flutter/material.dart';

/// Fallback / Stub implementation for non-web environments (mobile, desktop, unit tests).
Widget buildGoogleSignInButton({
  required VoidCallback onPressed,
  bool isLoading = false,
}) {
  return const SizedBox.shrink();
}
