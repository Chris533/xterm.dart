import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:xterm/src/base/disposable.dart';
import 'package:xterm/src/core/buffer/buffer.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/range_block.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/selection_mode.dart';

class TerminalController with ChangeNotifier {
  TerminalController({
    this.selectionBuffer,
    SelectionMode selectionMode = SelectionMode.line,
    PointerInputs pointerInputs = const PointerInputs({PointerInput.tap}),
    bool suspendPointerInput = false,
  })  : _selectionMode = selectionMode,
        _pointerInputs = pointerInputs,
        _suspendPointerInputs = suspendPointerInput;

  CellAnchor? _selectionBase;
  CellAnchor? _selectionExtent;

  /// Opt-in selected-text retention. Reads occur only for explicit selection
  /// changes and validation of selected rows, never via an output subscription.
  final Buffer Function()? selectionBuffer;
  Buffer? _selectionOwner;
  String? _selectedText;
  bool _selectionHidden = false;
  List<(BufferLine, int)> _selectedRows = [];
  BufferRange? _checkedRange;

  String? get selectedText {
    _checkOwner();
    return _selectedText;
  }

  bool get hasSelection =>
      selectedText?.isNotEmpty == true || selection?.isCollapsed == false;

  int get selectionRevision => _selectionRevision;
  int _selectionRevision = 0;

  bool get isSelectionHidden {
    final current = selection; // Validate before a gesture attempts to extend.
    return current == null && _selectionHidden;
  }

  void _checkOwner() {
    if (_selectionOwner != null &&
        !identical(_selectionOwner, selectionBuffer?.call())) {
      _selectedText = null;
      _selectedRows = [];
      _checkedRange = null;
      _selectionOwner = null;
      _selectionHidden = true;
      _selectionClearRevision++;
    }
  }

  void _rememberRows(Buffer buffer, BufferRange range) {
    final normalized = range.normalized;
    _selectedRows = [
      for (var y = normalized.begin.y; y <= normalized.end.y; y++)
        if (y >= 0 && y < buffer.height)
          (buffer.lines[y], buffer.lines[y].version),
    ];
    _checkedRange = range;
  }

  bool _sameRows(Buffer buffer, BufferRange range) {
    final normalized = range.normalized;
    if (_checkedRange?.begin.x != range.begin.x ||
        _checkedRange?.end.x != range.end.x ||
        normalized.end.y - normalized.begin.y + 1 != _selectedRows.length) {
      return false;
    }
    for (var i = 0; i < _selectedRows.length; i++) {
      final y = normalized.begin.y + i;
      if (y < 0 || y >= buffer.height) return false;
      final row = buffer.lines[y];
      final saved = _selectedRows[i];
      if (!identical(row, saved.$1) || row.version != saved.$2) return false;
    }
    return true;
  }

  /// Changes when a host selection is explicitly invalidated. Gesture origins
  /// use this to avoid resurrecting a range after an application redraw scroll.
  int get selectionClearRevision => _selectionClearRevision;
  int _selectionClearRevision = 0;

  SelectionMode get selectionMode => _selectionMode;
  SelectionMode _selectionMode;

  /// The set of pointer events which will be used as mouse input for the terminal.
  PointerInputs get pointerInput => _pointerInputs;
  PointerInputs _pointerInputs;

  /// True if sending pointer events to the terminal is suspended.
  bool get suspendedPointerInputs => _suspendPointerInputs;
  bool _suspendPointerInputs;

  List<TerminalHighlight> get highlights => _highlights;
  final _highlights = <TerminalHighlight>[];

  BufferRange? get selection {
    _checkOwner();
    if (_selectionHidden) return null;
    final base = _selectionBase;
    final extent = _selectionExtent;

    if (base == null || extent == null) {
      return null;
    }

    if (!base.attached || !extent.attached) {
      _selectionHidden = _selectedText != null;
      return null;
    }

    final range = _createRange(base.offset, extent.offset);
    final buffer = _selectionOwner;
    if (buffer != null && _selectedText != null && !_sameRows(buffer, range)) {
      if (buffer.getText(range) != _selectedText) {
        assert(() {
          debugPrint('Terminal selection hidden: selected cells replaced by redraw');
          return true;
        }());
        _selectionHidden = true;
        _selectedRows = [];
        return null;
      }
      _rememberRows(buffer, range);
    }
    return range;
  }

  /// Set selection on the terminal from [base] to [extent]. This method takes
  /// the ownership of [base] and [extent] and will dispose them when the
  /// selection is cleared or changed.
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    _selectionRevision++;
    _selectionBase?.dispose();
    _selectionBase = base;

    _selectionExtent?.dispose();
    _selectionExtent = extent;

    if (mode != null) {
      _selectionMode = mode;
    }

    _selectionHidden = false;
    _selectionOwner = selectionBuffer?.call();
    final range = _createRange(base.offset, extent.offset);
    _selectedText = range.isCollapsed ? null : _selectionOwner?.getText(range);
    _selectedRows = [];
    _checkedRange = null;
    if (_selectedText != null) _rememberRows(_selectionOwner!, range);

    notifyListeners();
  }

  BufferRange _createRange(CellOffset begin, CellOffset end) {
    switch (selectionMode) {
      case SelectionMode.line:
        return BufferRangeLine(begin, end);
      case SelectionMode.block:
        return BufferRangeBlock(begin, end);
    }
  }

  /// Controls how the terminal behaves when the user selects a range of text.
  /// The default is [SelectionMode.line]. Setting this to [SelectionMode.block]
  /// enables block selection mode.
  void setSelectionMode(SelectionMode newSelectionMode) {
    // If the new mode is the same as the old mode,
    // nothing has to be changed.
    if (_selectionMode == newSelectionMode) {
      return;
    }
    // Set the new mode.
    final current = selection;
    _selectionMode = newSelectionMode;
    _selectionRevision++;
    if (_selectedText != null) {
      if (current == null) {
        clearSelection();
        return;
      }
      final range = _createRange(current.begin, current.end);
      _selectedText = _selectionOwner!.getText(range);
      _rememberRows(_selectionOwner!, range);
    }
    notifyListeners();
  }

  /// Clears the current selection.
  void clearSelection() {
    _selectionRevision++;
    _selectionOwner = null;
    _selectedText = null;
    _selectedRows = [];
    _checkedRange = null;
    _selectionHidden = false;
    _selectionClearRevision++;
    _selectionBase?.dispose();
    _selectionBase = null;
    _selectionExtent?.dispose();
    _selectionExtent = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _selectionBase?.dispose();
    _selectionExtent?.dispose();
    _selectedRows = [];
    _selectedText = null;
    _selectionOwner = null;
    super.dispose();
  }

  // Select which type of pointer events are send to the terminal.
  void setPointerInputs(PointerInputs pointerInput) {
    _pointerInputs = pointerInput;
    notifyListeners();
  }

  // Toggle sending pointer events to the terminal.
  void setSuspendPointerInput(bool suspend) {
    _suspendPointerInputs = suspend;
    notifyListeners();
  }

  // Returns true if this type of PointerInput should be send to the Terminal.
  @internal
  bool shouldSendPointerInput(PointerInput pointerInput) {
    // Always return false if pointer input is suspended.
    return _suspendPointerInputs
        ? false
        : _pointerInputs.inputs.contains(pointerInput);
  }

  /// Creates a new highlight on the terminal from [p1] to [p2] with the given
  /// [color]. The highlight will be removed when the returned object is
  /// disposed.
  TerminalHighlight highlight({
    required CellAnchor p1,
    required CellAnchor p2,
    required Color color,
  }) {
    final highlight = TerminalHighlight(
      this,
      p1: p1,
      p2: p2,
      color: color,
    );

    _highlights.add(highlight);
    notifyListeners();

    highlight.registerCallback(() {
      _highlights.remove(highlight);
      notifyListeners();
    });

    return highlight;
  }
}

class TerminalHighlight with Disposable {
  final TerminalController owner;

  final CellAnchor p1;

  final CellAnchor p2;

  final Color color;

  TerminalHighlight(
    this.owner, {
    required this.p1,
    required this.p2,
    required this.color,
  });

  /// Returns the range of the highlight. May be null if the anchors that
  /// define the highlight are not attached to the terminal.
  BufferRange? get range {
    if (!p1.attached || !p2.attached) {
      return null;
    }
    return BufferRangeLine(p1.offset, p2.offset);
  }
}
