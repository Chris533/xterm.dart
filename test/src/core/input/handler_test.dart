import 'package:test/test.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('defaultInputHandler', () {
    test('supports numpad enter', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.keyInput(TerminalKey.numpadEnter);
      expect(output, ['\r']);
    });

    test('preserves Alt on cursor keys without changing plain or Ctrl keys',
        () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowUp);
      terminal.keyInput(TerminalKey.arrowUp, alt: true);
      terminal.keyInput(TerminalKey.arrowDown, alt: true);
      terminal.keyInput(TerminalKey.arrowUp, ctrl: true);
      terminal.keyInput(TerminalKey.arrowUp, ctrl: true, alt: true);

      // Full-screen TUIs may use both the alternate screen and application
      // cursor mode. They must still receive the Alt modifier.
      terminal.write('\x1b[?1049h\x1b[?1h');
      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.cursorKeysMode, isTrue);
      terminal.keyInput(TerminalKey.arrowUp, alt: true);

      expect(output, [
        '\x1b[A',
        '\x1b[1;3A',
        '\x1b[1;3B',
        '\x1b[1;5A',
        '\x1b[1;7A',
        '\x1b[1;3A',
      ]);
    });
  });

  group('KeytabInputHandler', () {
    test('can insert modifier code', () {
      final handler = KeytabInputHandler(
        Keytab.parse(r'key Home +AnyMod : "\E[1;*H"'),
      );

      final terminal = Terminal(inputHandler: handler);

      late String output;

      terminal.onOutput = (data) {
        output = data;
      };

      terminal.keyInput(TerminalKey.home, ctrl: true);

      expect(output, '\x1b[1;5H');

      terminal.keyInput(TerminalKey.home, shift: true);

      expect(output, '\x1b[1;2H');
    });
  });
}
