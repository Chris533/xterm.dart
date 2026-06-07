import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  static const double _autoScrollEdgeInset = 24;

  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;
  Offset? _lastDragLocalPosition;
  Timer? _selectionAutoScrollTimer;

  LongPressStartDetails? _lastLongPressStartDetails;

  /// Tracks the selection base offset for Shift+Click extension.
  CellOffset? _selectionBaseOffset;

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onTertiaryTapDown,
      onTertiaryTapUp: onTertiaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      // onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDragCancel: onDragCancel,
      onDoubleTapDown: onDoubleTapDown,
      onTripleTapDown: onTripleTapDown,
    );
  }

  @override
  void dispose() {
    _stopSelectionAutoScroll();
    super.dispose();
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // Check for Shift+Click to extend selection.
    if (HardwareKeyboard.instance.isShiftPressed &&
        _selectionBaseOffset != null) {
      renderTerminal.extendSelection(details.localPosition, _selectionBaseOffset!);
      return;
    }

    // Record the tap position as potential selection base for Shift+Click.
    _selectionBaseOffset = renderTerminal.getCellOffset(details.localPosition);

    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.middle);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
    // Update selection base for potential Shift+Click after double-click.
    _selectionBaseOffset = renderTerminal.getCellOffset(details.localPosition);
  }

  void onTripleTapDown(TapDownDetails details) {
    renderTerminal.selectLine(details.localPosition);
    // Update selection base for potential Shift+Click after triple-click.
    _selectionBaseOffset = renderTerminal.getCellOffset(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;
    _lastDragLocalPosition = details.localPosition;
    _startSelectionAutoScroll();

    // Record selection base for Shift+Click.
    _selectionBaseOffset = renderTerminal.getCellOffset(details.localPosition);

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragLocalPosition = details.localPosition;
    // Anchor the selection to the buffer cell captured at drag start rather than
    // re-deriving it from the start pixel every frame. The start pixel is
    // viewport-relative, so once the view scrolls it would resolve to a
    // different cell and the anchor would drift — breaking selections that span
    // more than one screen.
    final base = _selectionBaseOffset;
    if (base != null) {
      renderTerminal.extendSelection(details.localPosition, base);
    } else {
      renderTerminal.selectCharacters(
        _lastDragStartDetails!.localPosition,
        details.localPosition,
      );
    }
  }

  void onDragEnd(DragEndDetails details) {
    _stopSelectionAutoScroll();
  }

  void onDragCancel() {
    _stopSelectionAutoScroll();
  }

  void _startSelectionAutoScroll() {
    _selectionAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickSelectionAutoScroll(),
    );
  }

  void _stopSelectionAutoScroll() {
    _selectionAutoScrollTimer?.cancel();
    _selectionAutoScrollTimer = null;
    _lastDragLocalPosition = null;
  }

  void _tickSelectionAutoScroll() {
    final base = _selectionBaseOffset;
    final dragPosition = _lastDragLocalPosition;
    if (base == null || dragPosition == null) {
      return;
    }

    final viewportHeight = renderTerminal.size.height;
    if (viewportHeight <= 0) {
      return;
    }

    double delta = 0;
    if (dragPosition.dy < _autoScrollEdgeInset) {
      final overflow = (_autoScrollEdgeInset - dragPosition.dy)
          .clamp(0.0, _autoScrollEdgeInset);
      delta = -(overflow / _autoScrollEdgeInset) * renderTerminal.lineHeight;
    } else if (dragPosition.dy > viewportHeight - _autoScrollEdgeInset) {
      final overflow = (dragPosition.dy - (viewportHeight - _autoScrollEdgeInset))
          .clamp(0.0, _autoScrollEdgeInset);
      delta = (overflow / _autoScrollEdgeInset) * renderTerminal.lineHeight;
    }

    if (delta == 0 || !terminalView.scrollBy(delta)) {
      return;
    }

    // Extend from the fixed buffer-cell anchor to the current drag pixel. After
    // scrollBy() the scroll offset has changed, so the drag pixel now resolves
    // to the newly revealed cell while the anchor stays put.
    renderTerminal.extendSelection(
      Offset(
        dragPosition.dx,
        dragPosition.dy.clamp(0.0, viewportHeight - 1),
      ),
      base,
    );
  }
}
