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

    test('distinguishes Alt from Ctrl on horizontal arrows', () {
      final output = <String>[];
      final terminal = Terminal(
        platform: TerminalTargetPlatform.windows,
        onOutput: output.add,
      );

      terminal.keyInput(TerminalKey.arrowLeft, alt: true);
      terminal.keyInput(TerminalKey.arrowRight, alt: true);
      terminal.keyInput(TerminalKey.arrowLeft, ctrl: true);
      terminal.keyInput(TerminalKey.arrowRight, ctrl: true);

      expect(output, [
        '\x1b[1;3D',
        '\x1b[1;3C',
        '\x1b[1;5D',
        '\x1b[1;5C',
      ]);
    });

    test('keeps the macOS Alt+arrow word-navigation convention', () {
      final output = <String>[];
      final terminal = Terminal(
        platform: TerminalTargetPlatform.macos,
        onOutput: output.add,
      );

      terminal.keyInput(TerminalKey.arrowLeft, alt: true);
      terminal.keyInput(TerminalKey.arrowRight, alt: true);

      expect(output, ['\x1bb', '\x1bf']);
    });

    test('uses cursor-key mode independently of application keypad mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.arrowUp);
      terminal.write('\x1b[?1h');
      terminal.keyInput(TerminalKey.arrowUp);
      terminal.keyInput(TerminalKey.home);
      terminal.write('\x1b[?1l\x1b=');
      terminal.keyInput(TerminalKey.arrowUp);
      terminal.keyInput(TerminalKey.home);

      expect(output, ['\x1b[A', '\x1bOA', '\x1bOH', '\x1b[A', '\x1b[H']);
    });

    test('encodes modified F1-F4 as CSI function keys', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.f1);
      terminal.keyInput(TerminalKey.f1, alt: true);
      terminal.keyInput(TerminalKey.f2, ctrl: true);
      terminal.keyInput(TerminalKey.f3, shift: true);
      terminal.keyInput(TerminalKey.f4, ctrl: true, alt: true);
      terminal.keyInput(TerminalKey.f5, alt: true);

      expect(output, [
        '\x1bOP',
        '\x1b[1;3P',
        '\x1b[1;5Q',
        '\x1b[1;2R',
        '\x1b[1;7S',
        '\x1b[15;3~',
      ]);
    });

    test('encodes Alt+letters with their unshifted or shifted case', () {
      final output = <String>[];
      final terminal = Terminal(
        platform: TerminalTargetPlatform.windows,
        onOutput: output.add,
      );

      terminal.keyInput(TerminalKey.keyA, alt: true);
      terminal.keyInput(TerminalKey.keyZ, alt: true);
      terminal.keyInput(TerminalKey.keyA, alt: true, shift: true);

      expect(output, ['\x1ba', '\x1bz', '\x1bA']);
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
