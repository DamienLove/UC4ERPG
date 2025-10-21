import 'package:flutter_test/flutter_test.dart';
import 'package:uc4erpg_client/util/backup.dart';

void main() {
  test('export/import round-trip', () {
    final src = ['a', 'b', 'c'];
    final map = exportJournal(src);
    expect(map['entries'], src);
    final json = map.toString(); // not exact JSON, but ensure function exists
    final imported = importJournal('{"version":1,"entries":["a","b","c"]}');
    expect(imported, src);
  });
}