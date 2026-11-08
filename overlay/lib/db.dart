import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'parser.dart';

class DB {
  static Database? _d;
  static Future<Database> get db async => _d ??= await openDatabase(
        join(await getDatabasesPath(), 'fin.db'),
        version: 1,
        onCreate: (d, _) async {
          await d.execute('CREATE TABLE tx(id INTEGER PRIMARY KEY, hash TEXT UNIQUE, amount REAL, '
              'income INTEGER, merchant TEXT, category TEXT, ts INTEGER, raw TEXT)');
          await d.execute('CREATE TABLE rules(keyword TEXT PRIMARY KEY, category TEXT)');
        },
      );

  static Future<String> categorize(String merchant, bool income) async {
    if (income) return 'Renda';
    final d = await db;
    final k = norm(merchant);
    for (final r in await d.query('rules')) {
      if (k.contains(r['keyword'] as String)) return r['category'] as String;
    }
    for (final e in defaultRules.entries) {
      if (k.contains(e.key)) return e.value;
    }
    return 'Outros';
  }

  static Future<void> insert(Tx t) async {
    final d = await db;
    t.category = await categorize(t.merchant, t.income);
    await d.insert('tx', {
      'hash': '${t.ts}|${t.raw}', 'amount': t.amount, 'income': t.income ? 1 : 0,
      'merchant': t.merchant, 'category': t.category, 'ts': t.ts, 'raw': t.raw,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<List<Tx>> month(DateTime m) async {
    final d = await db;
    final a = m.millisecondsSinceEpoch;
    final b = DateTime(m.year, m.month + 1).millisecondsSinceEpoch;
    final rows = await d.query('tx', where: 'ts >= ? AND ts < ?', whereArgs: [a, b], orderBy: 'ts DESC');
    return rows.map((r) => Tx(id: r['id'] as int, amount: r['amount'] as double,
        income: r['income'] == 1, merchant: r['merchant'] as String,
        category: r['category'] as String, ts: r['ts'] as int, raw: r['raw'] as String)).toList();
  }

  /// Corrige a categoria e aprende: próximos lançamentos desse local já entram certos.
  static Future<void> setCategory(Tx t, String cat) async {
    final d = await db;
    await d.update('tx', {'category': cat}, where: 'merchant = ?', whereArgs: [t.merchant]);
    await d.insert('rules', {'keyword': norm(t.merchant), 'category': cat},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> delete(Tx t) async => (await db).delete('tx', where: 'id = ?', whereArgs: [t.id]);
}
