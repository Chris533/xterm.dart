import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('retained selection hides changed cells, not style or unrelated output',
      () {
    final terminal = Terminal();
    terminal.write('hello world\r\nother');
    final controller =
        TerminalController(selectionBuffer: () => terminal.buffer);
    controller.setSelection(
        terminal.buffer.createAnchor(0, 0), terminal.buffer.createAnchor(5, 0));
    terminal.write('\x1b[2;1Hchanged');
    expect(controller.selection, isNotNull);
    terminal.write('\x1b[H\x1b[31mhello');
    expect(controller.selection, isNotNull);
    terminal.write('\x1b[Hxxxxx');
    expect(controller.selection, isNull);
    expect(controller.selectedText, 'hello');
    terminal.write('\x1b[Hhello');
    expect(controller.selection, isNull,
        reason: 'do not guess text identity after invalidation');
    controller.clearSelection();
    expect(controller.selectedText, isNull);
    expect(controller.hasSelection, isFalse);
    controller.dispose();
  });

  test('retained selection clears on buffer switch and respects mode change',
      () {
    final terminal = Terminal();
    terminal.write('abcdef\r\nghijkl');
    final controller =
        TerminalController(selectionBuffer: () => terminal.buffer);
    controller.setSelection(
        terminal.buffer.createAnchor(1, 0), terminal.buffer.createAnchor(3, 1));
    controller.setSelectionMode(SelectionMode.block);
    expect(controller.selectedText, 'bc\nhi');
    terminal.write('\x1b[?1049hnew screen');
    expect(controller.hasSelection, isFalse);
    expect(controller.selectedText, isNull);
    terminal.write('\x1b[?1049l');
    expect(controller.selection, isNull);
    controller.dispose();
  });

  test('retained selection survives reflow and explicit clear frees anchors',
      () {
    final terminal = Terminal();
    terminal.resize(10, 5);
    terminal.write('abcdefghijklmnop');
    final controller =
        TerminalController(selectionBuffer: () => terminal.buffer);
    controller.setSelection(
        terminal.buffer.createAnchor(1, 0), terminal.buffer.createAnchor(3, 1));
    final text = controller.selectedText;
    terminal.resize(8, 5);
    expect(controller.selection, isNotNull);
    expect(controller.selectedText, text);
    controller.clearSelection();
    expect(controller.selectedText, isNull);
    for (final line in terminal.buffer.lines.toList()) {
      expect(line.anchors, isEmpty);
    }
    controller.dispose();
  });

  group('TerminalController', () {
    testWidgets('setSelectionRange works', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      await tester.pump();

      expect(terminalView.selection, isNotNull);
    });

    testWidgets('setSelectionMode changes BufferRange type', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(terminalView.selection, isA<BufferRangeLine>());

      terminalView.setSelectionMode(SelectionMode.block);

      expect(terminalView.selection, isA<BufferRangeBlock>());
    });

    testWidgets('clearSelection works', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(terminalView.selection, isNotNull);

      terminalView.clearSelection();

      expect(terminalView.selection, isNull);
    });
  });

  group('TerminalController.highlight', () {
    test('works', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final highlight = controller.highlight(
        p1: terminal.buffer.createAnchor(5, 5),
        p2: terminal.buffer.createAnchor(5, 10),
        color: Colors.yellow,
      );
      assert(controller.highlights.length == 1);

      highlight.dispose();
      assert(controller.highlights.isEmpty);
    });
  });
}
