import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Buffer.onRowEvicted', () {
    test('scrollUp reports overwritten region rows in top-down order', () {
      final terminal = Terminal();
      final buffer = terminal.buffer;
      for (var i = 0; i < 23; i++) {
        terminal.write('row ${i.toString().padLeft(2, '0')}\r\n');
      }
      terminal.write('row 23'); // fills the 24-row viewport, cursor stays

      final evicted = <String>[];
      buffer.onRowEvicted = (row) => evicted.add(row.getText());
      buffer.scrollUp(3);
      expect(evicted.map((t) => t.trim()), ['row 00', 'row 01', 'row 02']);
      // Region rows shifted up; the reported rows captured their final
      // pre-overwrite text.
      expect(buffer.lines[0].getText().trim(), 'row 03');
    });

    test('alt-buffer scroll-out reports rows destroyed in place', () {
      final terminal = Terminal();
      final evicted = <String>[];
      terminal.altBuffer.onRowEvicted = (row) => evicted.add(row.getText());

      terminal.write('\x1b[?1049h');
      for (var i = 0; i < 30; i++) {
        terminal.write('alt ${i.toString().padLeft(2, '0')}\r\n');
      }
      // 30 content rows + the trailing blank row through a 24-row alt
      // viewport destroy the top 7 rows — alt has no scrollback.
      expect(evicted.length, 7);
      expect(evicted.first.trim(), 'alt 00');
      expect(evicted[1].trim(), 'alt 01');
      expect(evicted.last.trim(), 'alt 06');
    });

    test('main-buffer cap eviction reports the dropped front row', () {
      final terminal = Terminal(maxLines: 26);
      final evicted = <String>[];
      terminal.mainBuffer.onRowEvicted =
          (row) => evicted.add(row.getText());

      for (var i = 0; i < 30; i++) {
        terminal.write('cap ${i.toString().padLeft(2, '0')}\r\n');
      }
      // 30 content rows + the trailing blank row vs 26-row capacity →
      // the five oldest rows evict, in order, as pushes overflow.
      expect(evicted.length, 5);
      expect(evicted.map((t) => t.trim()), [
        'cap 00',
        'cap 01',
        'cap 02',
        'cap 03',
        'cap 04',
      ]);
    });

    test('clear drains content rows then bumps generation', () {
      final terminal = Terminal();
      final buffer = terminal.buffer;
      final seen = <(int, String)>[];
      buffer.onRowEvicted =
          (row) => seen.add((buffer.generation, row.getText()));

      terminal.write('first\r\nsecond\r\nthird\r\n');
      final genBefore = buffer.generation;
      buffer.clear();

      // Drained rows are tagged with the OUTGOING generation — the bump
      // happens after the drain — and trailing blank rows are skipped.
      expect(seen.map((s) => s.$1).toSet(), {genBefore});
      expect(
        seen.map((s) => s.$2.trim()),
        ['first', 'second', 'third'],
      );
      expect(buffer.generation, genBefore + 1);
      expect(buffer.height, buffer.viewHeight);
    });

    test('clearScrollback drains only scrollback rows', () {
      final terminal = Terminal(maxLines: 100);
      final buffer = terminal.buffer;
      for (var i = 0; i < 40; i++) {
        terminal.write('sb ${i.toString().padLeft(2, '0')}\r\n');
      }
      expect(buffer.scrollBack, greaterThan(0));
      final evicted = <String>[];
      buffer.onRowEvicted = (row) => evicted.add(row.getText());
      buffer.clearScrollback();
      expect(buffer.scrollBack, 0);
      // 41 rows (40 content + trailing blank) - 24 viewport = 17
      // scrollback rows drained in order.
      expect(evicted.length, 17);
      expect(evicted.first.trim(), 'sb 00');
      expect(evicted.last.trim(), 'sb 16');
      // Viewport rows survive.
      expect(buffer.getText(), contains('sb 39'));
    });

    test('resize bumps generation only when dimensions change', () {
      final terminal = Terminal();
      final buffer = terminal.buffer;
      final gen = buffer.generation;
      terminal.resize(80, 24); // default size — no change
      expect(buffer.generation, gen);
      terminal.resize(120, 24);
      expect(buffer.generation, gen + 1);
      // Both buffers bump, including the parked one.
      expect(terminal.altBuffer.generation, greaterThan(0));
    });
  });
}
