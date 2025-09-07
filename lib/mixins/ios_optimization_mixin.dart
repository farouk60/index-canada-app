import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

/// Mixin pour optimiser les pages pour iOS
mixin IOSOptimizationMixin<S extends StatefulWidget> on State<S> {
  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      _optimizeForIOS();
    }
  }

  /// Applique des optimisations spécifiques à iOS
  void _optimizeForIOS() {
    // Optimiser la barre de statut pour iOS
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }

  /// Créer un bouton de retour iOS-style
  Widget buildIOSBackButton({VoidCallback? onPressed}) {
    if (Platform.isIOS) {
      return IconButton(
        icon: const Icon(Icons.arrow_back_ios),
        onPressed: onPressed ?? () => Navigator.of(context).pop(),
      );
    }
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
    );
  }

  /// Créer une AppBar optimisée pour iOS
  PreferredSizeWidget buildIOSOptimizedAppBar({
    required String title,
    List<Widget>? actions,
    bool automaticallyImplyLeading = true,
  }) {
    if (Platform.isIOS) {
      return AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: actions,
        automaticallyImplyLeading: automaticallyImplyLeading,
        leading: automaticallyImplyLeading ? buildIOSBackButton() : null,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }

    return AppBar(
      title: Text(title),
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
  }

  /// Afficher un dialog optimisé pour iOS
  Future<T?> showIOSOptimizedDialog<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
  }) {
    if (Platform.isIOS) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (context) => child,
      );
    }

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => child,
    );
  }

  /// Vibration optimisée pour iOS
  void performIOSHapticFeedback({IOSHapticType? type}) {
    if (Platform.isIOS) {
      switch (type) {
        case IOSHapticType.lightImpact:
          HapticFeedback.lightImpact();
          break;
        case IOSHapticType.mediumImpact:
          HapticFeedback.mediumImpact();
          break;
        case IOSHapticType.heavyImpact:
          HapticFeedback.heavyImpact();
          break;
        default:
          HapticFeedback.selectionClick();
      }
    } else {
      HapticFeedback.selectionClick();
    }
  }
}

enum IOSHapticType { lightImpact, mediumImpact, heavyImpact, selectionClick }
