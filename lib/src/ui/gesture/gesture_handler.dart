import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
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
    this.enabled = true,
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
  final bool enabled;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  static const double _autoScrollEdgeInset = 24;

  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  Offset? _lastDragLocalPosition;
  Timer? _selectionAutoScrollTimer;

  LongPressStartDetails? _lastLongPressStartDetails;

  // Independently owned anchors survive scrollback eviction/reflow. Never
  // retain anchors owned by TerminalController: setSelection disposes those.
  CellAnchor? _selectionBase;
  CellAnchor? _selectionEnd;
  Object? _originBuffer;
  TapDownDetails? _pendingLeftTap;
  bool _hostLeftGesture = false;
  bool _previewTap = false;

  bool get _previewModifierHeld => defaultTargetPlatform == TargetPlatform.macOS
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  void _setOrigin(CellOffset begin, [CellOffset? end]) {
    _clearOrigin();
    final buffer = terminalView.widget.terminal.buffer;
    _originBuffer = buffer;
    _selectionBase = buffer.createAnchorFromOffset(begin);
    if (end != null) _selectionEnd = buffer.createAnchorFromOffset(end);
  }

  void _clearOrigin() {
    _selectionBase?.dispose();
    _selectionEnd?.dispose();
    _selectionBase = null;
    _selectionEnd = null;
    _originBuffer = null;
  }

  CellOffset? get _base {
    if (_originBuffer != terminalView.widget.terminal.buffer ||
        _selectionBase?.attached != true ||
        (_selectionEnd != null && !_selectionEnd!.attached)) {
      if (_originBuffer != null) widget.terminalController.clearSelection();
      _clearOrigin();
      return null;
    }
    return _selectionBase!.offset;
  }

  void _extend(Offset position) {
    final base = _base;
    if (base == null) {
      _stopSelectionAutoScroll();
      return;
    }
    renderTerminal.extendSelection(position, base,
        originEnd: _selectionEnd?.offset);
  }

  @override
  void didUpdateWidget(TerminalGestureHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.terminalController != widget.terminalController) {
      onDragCancel();
      _clearOrigin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onTapCancel: onTapCancel,
      isExclusiveTap: () => _previewModifierHeld,
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
    _clearOrigin();
    super.dispose();
  }

  bool get _shouldSendTapEvent =>
      widget.enabled &&
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

  void onSingleTapUp(TapUpDetails details) {
    if (!widget.enabled || _hostLeftGesture) {
      _pendingLeftTap = null;
      _hostLeftGesture = false;
      return;
    }
    // Report only a resolved click. A held pointer that becomes a host drag
    // must never leak an unmatched mouse press into the application.
    final down = _pendingLeftTap;
    _pendingLeftTap = null;
    if (down == null) return;
    if (_previewTap) {
      _previewTap = false;
      // Host preview owns the resolved tap; do not also mutate a mouse TUI.
      if (_previewModifierHeld) {
        (widget.onTapUp ?? widget.onSingleTapUp)?.call(details);
      }
      return;
    }
    _tapDown(null, down, TerminalMouseButton.left);
    _tapUp(
      widget.onTapUp ?? widget.onSingleTapUp,
      details,
      TerminalMouseButton.left,
    );
  }

  void onTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    _pendingLeftTap = details;
    _previewTap = _previewModifierHeld;
    _hostLeftGesture = !_previewTap && HardwareKeyboard.instance.isShiftPressed;
    if (_previewTap) {
      widget.onTapDown?.call(details);
      return;
    }
    // Check for Shift+Click to extend selection.
    if (HardwareKeyboard.instance.isShiftPressed && _base != null) {
      _extend(details.localPosition);
      return;
    }

    // Record the tap position as potential selection base for Shift+Click.
    _setOrigin(renderTerminal.getSelectionCellOffset(details.localPosition));

    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    widget.onTapDown?.call(details);
  }

  void onTapCancel() {
    _pendingLeftTap = null;
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
    if (!widget.enabled) return;
    _hostLeftGesture = true;
    _pendingLeftTap = null;
    renderTerminal.selectWord(details.localPosition);
    // Update selection base for potential Shift+Click after double-click.
    final selection = widget.terminalController.selection?.normalized;
    if (selection != null) _setOrigin(selection.begin, selection.end);
  }

  void onTripleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    _hostLeftGesture = true;
    _pendingLeftTap = null;
    renderTerminal.selectLine(details.localPosition);
    // Update selection base for potential Shift+Click after triple-click.
    final selection = widget.terminalController.selection?.normalized;
    if (selection != null) _setOrigin(selection.begin, selection.end);
  }

  void onLongPressStart(LongPressStartDetails details) {
    if (!widget.enabled) return;
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!widget.enabled || _lastLongPressStartDetails == null) return;
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _pendingLeftTap = null;
    _hostLeftGesture = true;
    _lastDragLocalPosition = details.localPosition;

    // Record selection base for Shift+Click.
    _setOrigin(renderTerminal.getSelectionCellOffset(details.localPosition));

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
    _updateSelectionAutoScroll();
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _lastDragLocalPosition == null) return;
    _lastDragLocalPosition = details.localPosition;
    // Anchor the selection to the buffer cell captured at drag start rather than
    // re-deriving it from the start pixel every frame. The start pixel is
    // viewport-relative, so once the view scrolls it would resolve to a
    // different cell and the anchor would drift — breaking selections that span
    // more than one screen.
    _extend(details.localPosition);
    _updateSelectionAutoScroll();
  }

  void onDragEnd(DragEndDetails details) {
    _stopSelectionAutoScroll();
    _hostLeftGesture = false;
  }

  void onDragCancel() {
    _stopSelectionAutoScroll();
    _pendingLeftTap = null;
    _hostLeftGesture = false;
  }

  void _updateSelectionAutoScroll() {
    final position = _lastDragLocalPosition;
    if (position == null) return;
    final height = renderTerminal.size.height;
    if (position.dy < _autoScrollEdgeInset ||
        position.dy > height - _autoScrollEdgeInset) {
      _startSelectionAutoScroll();
    } else {
      _selectionAutoScrollTimer?.cancel();
      _selectionAutoScrollTimer = null;
    }
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
    if (!widget.enabled) {
      _stopSelectionAutoScroll();
      return;
    }
    final base = _base;
    final dragPosition = _lastDragLocalPosition;
    if (base == null || dragPosition == null) {
      _stopSelectionAutoScroll();
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
      final overflow =
          (dragPosition.dy - (viewportHeight - _autoScrollEdgeInset))
              .clamp(0.0, _autoScrollEdgeInset);
      delta = (overflow / _autoScrollEdgeInset) * renderTerminal.lineHeight;
    }

    if (delta == 0 || !terminalView.scrollBy(delta)) {
      return;
    }

    // Extend from the fixed buffer-cell anchor to the current drag pixel. After
    // scrollBy() the scroll offset has changed, so the drag pixel now resolves
    // to the newly revealed cell while the anchor stays put.
    _extend(
      Offset(
        dragPosition.dx,
        dragPosition.dy.clamp(0.0, viewportHeight - 1),
      ),
    );
  }
}
