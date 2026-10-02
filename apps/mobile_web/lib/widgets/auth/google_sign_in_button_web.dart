import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;

/// Web implementation utilizing the official Google Identity Services (GIS) button renderer.
/// Guarantees return of genuine OIDC ID Token JWTs for backend server verification.
Widget buildGoogleSignInButton({
  required VoidCallback onPressed,
  bool isLoading = false,
}) {
  return SizedBox(
    height: 44,
    width: double.infinity,
    child: Center(
      child: web_only.renderButton(
        configuration: web_only.GSIButtonConfiguration(
          type: web_only.GSIButtonType.standard,
          theme: web_only.GSIButtonTheme.outline,
          size: web_only.GSIButtonSize.large,
          text: web_only.GSIButtonText.continueWith,
          shape: web_only.GSIButtonShape.rectangular,
          logoAlignment: web_only.GSIButtonLogoAlignment.left,
          minimumWidth: 372,
        ),
      ),
    ),
  );
}
