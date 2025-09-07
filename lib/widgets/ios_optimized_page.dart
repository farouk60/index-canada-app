import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';
import '../services/ios_optimization_service.dart';
import '../mixins/ios_optimization_mixin.dart';

/// Widget de page optimisé spécifiquement pour iOS
class IOSOptimizedPage extends StatefulWidget {
  final Widget child;
  final String title;
  final AppBar? appBar;
  final FloatingActionButton? floatingActionButton;
  final Widget? drawer;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool showAppBar;
  final List<Widget>? actions;
  final Widget? leading;

  const IOSOptimizedPage({
    super.key,
    required this.child,
    required this.title,
    this.appBar,
    this.floatingActionButton,
    this.drawer,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.showAppBar = true,
    this.actions,
    this.leading,
  });

  @override
  State<IOSOptimizedPage> createState() => _IOSOptimizedPageState();
}

class _IOSOptimizedPageState extends State<IOSOptimizedPage>
    with IOSOptimizationMixin<IOSOptimizedPage> {
  @override
  Widget build(BuildContext context) {
    // Si c'est iOS, utiliser les optimisations iOS
    if (Platform.isIOS) {
      return CupertinoPageScaffold(
        navigationBar: widget.showAppBar ? _buildIOSNavigationBar() : null,
        backgroundColor:
            widget.backgroundColor ??
            (IOSOptimizationService.isIOSDarkMode(context)
                ? CupertinoColors.systemBackground
                : CupertinoColors.systemGroupedBackground),
        child: SafeArea(
          child: AnimatedContainer(
            duration: IOSOptimizationService.getIOSAnimationDuration(),
            curve: IOSOptimizationService.getIOSAnimationCurve(),
            child: widget.child,
          ),
        ),
      );
    }

    // Pour Android et autres plateformes, utiliser Material Design
    return Scaffold(
      appBar: widget.showAppBar
          ? (widget.appBar ?? _buildMaterialAppBar())
          : null,
      body: widget.child,
      floatingActionButton: widget.floatingActionButton,
      drawer: widget.drawer,
      bottomNavigationBar: widget.bottomNavigationBar,
      backgroundColor: widget.backgroundColor,
    );
  }

  /// Construit une barre de navigation iOS native
  CupertinoNavigationBar _buildIOSNavigationBar() {
    return CupertinoNavigationBar(
      middle: Text(
        widget.title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      leading:
          widget.leading ??
          (Navigator.canPop(context)
              ? CupertinoNavigationBarBackButton(
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null),
      trailing: widget.actions?.isNotEmpty == true
          ? Row(mainAxisSize: MainAxisSize.min, children: widget.actions!)
          : null,
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      border: const Border(
        bottom: BorderSide(color: CupertinoColors.separator, width: 0.5),
      ),
    );
  }

  /// Construit une AppBar Material Design de fallback
  AppBar _buildMaterialAppBar() {
    return AppBar(
      title: Text(widget.title),
      leading: widget.leading,
      actions: widget.actions,
      backgroundColor: widget.backgroundColor,
    );
  }
}

/// Widget pour conteneur optimisé iOS
class IOSOptimizedContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? width;
  final double? height;
  final BoxDecoration? decoration;

  const IOSOptimizedContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.width,
    this.height,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? IOSOptimizationService.getIOSPadding(),
      margin: margin,
      decoration:
          decoration ??
          BoxDecoration(
            color:
                color ??
                (Platform.isIOS
                    ? CupertinoColors.systemBackground.resolveFrom(context)
                    : Theme.of(context).cardColor),
            borderRadius: IOSOptimizationService.getIOSBorderRadius(),
            boxShadow: IOSOptimizationService.getIOSShadow(),
          ),
      child: child,
    );
  }
}

/// Widget de bouton optimisé pour iOS
class IOSOptimizedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color? color;
  final Color? textColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool isDestructive;

  const IOSOptimizedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoButton(
        onPressed: onPressed,
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color:
            color ??
            (isDestructive
                ? CupertinoColors.destructiveRed
                : CupertinoColors.activeBlue),
        borderRadius: BorderRadius.circular(borderRadius ?? 12),
        child: DefaultTextStyle(
          style: TextStyle(
            color: textColor ?? CupertinoColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          child: child,
        ),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 8),
        ),
      ),
      child: child,
    );
  }
}

/// Widget de liste optimisé pour iOS
class IOSOptimizedListView extends StatelessWidget {
  final List<Widget> children;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;

  const IOSOptimizedListView({
    super.key,
    required this.children,
    this.physics,
    this.padding,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          physics ??
          (Platform.isIOS
              ? const BouncingScrollPhysics()
              : const ClampingScrollPhysics()),
      padding: padding ?? IOSOptimizationService.getIOSPadding(),
      shrinkWrap: shrinkWrap,
      children: children,
    );
  }
}
