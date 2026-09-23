import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

extension EngagementVisibilityTracking on Widget {
  Widget trackEngagementVisibility({
    Key? key,
    required VoidCallback onQualifiedVisibility,
  }) {
    return EngagementVisibilityTracker(
      key: key,
      onQualifiedVisibility: onQualifiedVisibility,
      child: this,
    );
  }
}

/// Déclenche une impression lorsque [child] demeure suffisamment visible.
///
/// Une instance ne déclenche jamais plus d'une impression. La page qui
/// contient plusieurs instances d'une même fiche reste responsable de la
/// déduplication par identifiant et emplacement.
class EngagementVisibilityTracker extends StatefulWidget {
  const EngagementVisibilityTracker({
    super.key,
    required this.child,
    required this.onQualifiedVisibility,
    this.minimumVisibleFraction = 0.5,
    this.minimumVisibleDuration = const Duration(seconds: 1),
  }) : assert(
         minimumVisibleFraction > 0 && minimumVisibleFraction <= 1,
         'minimumVisibleFraction doit être compris entre 0 et 1',
       );

  final Widget child;
  final VoidCallback onQualifiedVisibility;
  final double minimumVisibleFraction;
  final Duration minimumVisibleDuration;

  @override
  State<EngagementVisibilityTracker> createState() =>
      _EngagementVisibilityTrackerState();
}

class _EngagementVisibilityTrackerState
    extends State<EngagementVisibilityTracker>
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(milliseconds: 100);

  final GlobalKey _probeKey = GlobalKey();
  Timer? _pollTimer;
  Duration _continuousVisibility = Duration.zero;
  bool _hasVisibleSample = false;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pollVisibility();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _pollVisibility());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _resetCandidate();
  }

  void _pollVisibility() {
    if (!mounted || _reported) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    final route = ModalRoute.of(context);
    final isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    final isCurrentRoute = route == null || route.isCurrent;
    if (!isForeground || !isCurrentRoute) {
      _resetCandidate();
      return;
    }

    final renderObject = _probeKey.currentContext?.findRenderObject();
    final fraction = renderObject is _RenderVisibilityProbe
        ? renderObject.visibleFraction
        : 0.0;

    if (fraction < widget.minimumVisibleFraction) {
      _resetCandidate();
      return;
    }

    if (!_hasVisibleSample) {
      _hasVisibleSample = true;
      return;
    }

    _continuousVisibility += _pollInterval;
    if (_continuousVisibility < widget.minimumVisibleDuration) return;

    _reported = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      widget.onQualifiedVisibility();
    } catch (_) {
      // La mesure ne doit jamais affecter l'interface principale.
    }
  }

  void _resetCandidate() {
    _continuousVisibility = Duration.zero;
    _hasVisibleSample = false;
  }

  @override
  Widget build(BuildContext context) {
    final viewportSize =
        MediaQuery.maybeSizeOf(context) ??
        View.of(context).physicalSize / View.of(context).devicePixelRatio;

    return _VisibilityProbe(
      key: _probeKey,
      viewportSize: viewportSize,
      child: widget.child,
    );
  }
}

class _VisibilityProbe extends SingleChildRenderObjectWidget {
  const _VisibilityProbe({
    super.key,
    required this.viewportSize,
    required super.child,
  });

  final Size viewportSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderVisibilityProbe(viewportSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderVisibilityProbe renderObject,
  ) {
    renderObject.viewportSize = viewportSize;
  }
}

class _RenderVisibilityProbe extends RenderProxyBox {
  _RenderVisibilityProbe(this._viewportSize);

  Size _viewportSize;

  set viewportSize(Size value) {
    if (_viewportSize == value) return;
    _viewportSize = value;
    markNeedsPaint();
  }

  double get visibleFraction {
    if (!attached || !hasSize || size.isEmpty) return 0;

    var visibleRect = localToGlobal(Offset.zero) & size;
    if (!_isFiniteRect(visibleRect)) return 0;
    visibleRect = visibleRect.intersect(Offset.zero & _viewportSize);

    RenderObject childInAncestor = this;
    RenderObject? ancestor = parent;
    while (ancestor != null && !visibleRect.isEmpty) {
      if (!ancestor.paintsChild(childInAncestor)) return 0;
      if (ancestor is RenderIndexedStack &&
          !_isDisplayedIndexedStackChild(ancestor, childInAncestor)) {
        return 0;
      }
      final clip = ancestor.describeApproximatePaintClip(childInAncestor);
      if (clip != null) {
        final globalClip = MatrixUtils.transformRect(
          ancestor.getTransformTo(null),
          clip,
        );
        if (!_isFiniteRect(globalClip)) return 0;
        visibleRect = visibleRect.intersect(globalClip);
      }
      childInAncestor = ancestor;
      ancestor = ancestor.parent;
    }

    if (visibleRect.isEmpty) return 0;
    final totalArea = size.width * size.height;
    if (totalArea <= 0) return 0;
    return (visibleRect.width * visibleRect.height / totalArea)
        .clamp(0, 1)
        .toDouble();
  }
}

bool _isDisplayedIndexedStackChild(
  RenderIndexedStack stack,
  RenderObject child,
) {
  final selectedIndex = stack.index;
  if (selectedIndex == null) return false;
  RenderBox? selectedChild = stack.firstChild;
  for (var index = 0; index < selectedIndex && selectedChild != null; index++) {
    selectedChild = stack.childAfter(selectedChild);
  }
  return identical(selectedChild, child);
}

bool _isFiniteRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite;
