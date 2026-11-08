import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'cat.dart';
import 'parser.dart';

class Goal {
  final int id;
  final String name;
  final double target;
  final double saved;
  final int? deadline; // ms desde epoch
  Goal(this.id, this.name, this.target, this.saved, this.deadline);
  double get pct => target <= 0 ? 0 : (saved / target).clamp(0, 1).toDouble();
}

class Rec {
  final int id;
  final String name;
  final double amount;
  final int day;
  final String category;
  final bool income, auto;
  final int start; // ano*12 + (mês-1) do primeiro lançamento
  final int? total; // nº de parcelas (null = sem fim)
  Rec(this.id, this.name, this.amount, this.day, this.category, this.income, this.auto, this.start, this.total);

  DateTime dueDate(int idx) {
    final y = idx ~/ 12;
    final m = idx % 12 + 1;
    final dim = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day > dim ? dim : day, 9);
  }
}

class Pend {
  final Rec rec;
  final int idx;
  final DateTime due;
  Pend(this.rec, this.idx, this.due);
}

const _goalsSql = 'CREATE TABLE goals(id INTEGER PRIMARY KEY, name TEXT, target REAL, '
    'saved REAL DEFAULT 0, deadline INTEGER)';
const _catsSql = 'CREATE TABLE categories(name TEXT PRIMARY KEY, icon TEXT, color INTEGER, limit_amount REAL)';
const _settingsSql = 'CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)';
const _recSql = 'CREATE TABLE recurring(id INTEGER PRIMARY KEY, name TEXT, amount REAL, day INTEGER, '
    'category TEXT, income INTEGER, auto INTEGER, start INTEGER, total INTEGER)';

Future<void> _seed(DatabaseExecutor d) async {
  for (final s in seedCats) {
    await d.insert('categories', {'name': s.name, 'icon': s.icon, 'color': s.color},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

class DB {
  static Database? _d;
  static Future<Database> get db async => _d ??= await openDatabase(
        join(await getDatabasesPath(), 'fin.db'),
        version: 4,
        onCreate: (d, _) async {
          await d.execute('CREATE TABLE tx(id INTEGER PRIMARY KEY, hash TEXT UNIQUE, amount REAL, '
              'income INTEGER, merchant TEXT, category TEXT, ts INTEGER, raw TEXT)');
          await d.execute('CREATE TABLE rules(keyword TEXT PRIMARY KEY, category TEXT)');
          await d.execute(_goalsSql);
          await d.execute(_catsSql);
          await d.execute(_settingsSql);
          await _seed(d);
          await d.execute(_recSql);
        },
        onUpgrade: (d, old, _) async {
          if (old < 2) await d.execute(_goalsSql);
          if (old < 3) {
            await d.execute(_catsSql);
            await d.execute(_settingsSql);
            await _seed(d);
          }
          if (old < 4) await d.execute(_recSql);
        },
      );

  // ---- Configurações ----
  static Future<String?> getSetting(String k) async {
    final r = await (await db).query('settings', where: 'k = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String;
  }

  static Future<void> setSetting(String k, String v) async => (await db)
      .insert('settings', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- Categorias ----
  static Future<List<Cat>> cats() async {
    final rows = await (await db).query('categories', orderBy: 'rowid');
    return rows.map((r) => Cat(r['name'] as String, r['icon'] as String, r['color'] as int,
        (r['limit_amount'] as num?)?.toDouble())).toList();
  }

  static Future<bool> addCat(Cat c) async {
    final d = await db;
    final ex = await d.query('categories', where: 'name = ?', whereArgs: [c.name]);
    if (ex.isNotEmpty) return false;
    await d.insert('categories',
        {'name': c.name, 'icon': c.icon, 'color': c.color, 'limit_amount': c.limit});
    return true;
  }

  static Future<void> updateCat(String old, Cat c) async {
    final d = await db;
    await d.transaction((t) async {
      await t.update('categories',
          {'name': c.name, 'icon': c.icon, 'color': c.color, 'limit_amount': c.limit},
          where: 'name = ?', whereArgs: [old]);
      if (old != c.name) {
        await t.update('tx', {'category': c.name}, where: 'category = ?', whereArgs: [old]);
        await t.update('rules', {'category': c.name}, where: 'category = ?', whereArgs: [old]);
        await t.update('recurring', {'category': c.name}, where: 'category = ?', whereArgs: [old]);
      }
    });
  }

  static Future<void> deleteCat(String name) async {
    final d = await db;
    await d.transaction((t) async {
      await t.update('tx', {'category': 'Outros'}, where: 'category = ?', whereArgs: [name]);
      await t.delete('rules', where: 'category = ?', whereArgs: [name]);
      await t.update('recurring', {'category': 'Outros'}, where: 'category = ?', whereArgs: [name]);
      await t.delete('categories', where: 'name = ?', whereArgs: [name]);
    });
  }

  static Future<bool> _exists(Database d, String name) async =>
      (await d.query('categories', where: 'name = ?', whereArgs: [name])).isNotEmpty;

  // ---- Lançamentos ----
  static Future<String> categorize(String merchant, bool income) async {
    if (income) return 'Renda';
    final d = await db;
    final k = norm(merchant);
    for (final r in await d.query('rules')) {
      if (k.contains(r['keyword'] as String)) return r['category'] as String;
    }
    for (final e in defaultRules.entries) {
      if (k.contains(e.key) && await _exists(d, e.value)) return e.value;
    }
    return 'Outros';
  }

  static Future<void> insert(Tx t, {String? category}) async {
    final d = await db;
    // Notificação do banco de uma conta agendada já lançada: não duplica.
    final fromNotification = !t.raw.startsWith('manual|') && !t.raw.startsWith('rec|');
    if (fromNotification) {
      final dup = await d.rawQuery(
          "SELECT 1 FROM tx WHERE raw LIKE 'rec|%' AND income = ? AND ABS(amount - ?) < 0.01 "
          'AND ts BETWEEN ? AND ? LIMIT 1',
          [t.income ? 1 : 0, t.amount, t.ts - _win, t.ts + _win]);
      if (dup.isNotEmpty) return;
    }
    t.category = category ?? await categorize(t.merchant, t.income);
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

  // ---- Metas de economia ----
  static Future<List<Goal>> goals() async {
    final d = await db;
    final rows = await d.query('goals', orderBy: 'id DESC');
    return rows.map((r) => Goal(r['id'] as int, r['name'] as String, (r['target'] as num).toDouble(),
        (r['saved'] as num).toDouble(), r['deadline'] as int?)).toList();
  }

  static Future<void> addGoal(String name, double target, DateTime? deadline) async =>
      (await db).insert('goals', {
        'name': name, 'target': target, 'saved': 0, 'deadline': deadline?.millisecondsSinceEpoch,
      });

  static Future<void> addToGoal(int id, double delta) async => (await db).rawUpdate(
      'UPDATE goals SET saved = MAX(0, saved + ?) WHERE id = ?', [delta, id]);

  static Future<void> deleteGoal(int id) async =>
      (await db).delete('goals', where: 'id = ?', whereArgs: [id]);

  // ---- Contas agendadas / recorrentes ----
  static const _win = 4 * 24 * 3600 * 1000; // janela de 4 dias para evitar duplicidade

  static Future<List<Rec>> recs() async {
    final rows = await (await db).query('recurring', orderBy: 'day, id');
    return rows.map((r) => Rec(r['id'] as int, r['name'] as String, (r['amount'] as num).toDouble(),
        r['day'] as int, r['category'] as String, r['income'] == 1, r['auto'] == 1,
        r['start'] as int, r['total'] as int?)).toList();
  }

  static Future<void> addRec(Rec r) async => (await db).insert('recurring', {
        'name': r.name, 'amount': r.amount, 'day': r.day, 'category': r.category,
        'income': r.income ? 1 : 0, 'auto': r.auto ? 1 : 0, 'start': r.start, 'total': r.total,
      });

  static Future<void> deleteRec(int id) async =>
      (await db).delete('recurring', where: 'id = ?', whereArgs: [id]);

  static Future<Map<int, int>> recCounts() async {
    final rows = await (await db).query('tx', columns: ['raw'], where: "raw LIKE 'rec|%'");
    final m = <int, int>{};
    for (final r in rows) {
      final id = int.tryParse((r['raw'] as String).split('|')[1]);
      if (id != null) m[id] = (m[id] ?? 0) + 1;
    }
    return m;
  }

  /// Já foi lançada (pela agenda) ou o banco já avisou um valor igual perto da data?
  static Future<bool> _covered(Database d, Rec r, int idx) async {
    final a = await d.query('tx', where: 'raw = ?', whereArgs: ['rec|${r.id}|$idx'], limit: 1);
    if (a.isNotEmpty) return true;
    final ts = r.dueDate(idx).millisecondsSinceEpoch;
    final b = await d.rawQuery(
        "SELECT 1 FROM tx WHERE raw NOT LIKE 'rec|%' AND income = ? AND ABS(amount - ?) < 0.01 "
        'AND ts BETWEEN ? AND ? LIMIT 1',
        [r.income ? 1 : 0, r.amount, ts - _win, ts + _win]);
    return b.isNotEmpty;
  }

  static Future<void> _insertRec(Database d, Rec r, int idx, int ts) async {
    var cat = r.income ? 'Renda' : r.category;
    if (!await _exists(d, cat)) cat = r.income ? 'Renda' : 'Outros';
    final raw = 'rec|${r.id}|$idx';
    await d.insert('tx', {
      'hash': raw, 'amount': r.amount, 'income': r.income ? 1 : 0,
      'merchant': r.name, 'category': cat, 'ts': ts, 'raw': raw,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Lança as contas automáticas cujo dia já chegou.
  static Future<void> generateDue() async {
    final d = await db;
    final now = DateTime.now();
    final nowIdx = now.year * 12 + now.month - 1;
    for (final r in await recs()) {
      if (!r.auto) continue;
      for (var idx = r.start; idx <= nowIdx; idx++) {
        if (r.total != null && idx - r.start + 1 > r.total!) break;
        final due = r.dueDate(idx);
        if (due.isAfter(now)) break;
        if (await _covered(d, r, idx)) continue;
        await _insertRec(d, r, idx, due.millisecondsSinceEpoch);
      }
    }
  }

  /// Contas ainda não lançadas no mês (atual ou futuro).
  static Future<List<Pend>> pending(int monthIdx) async {
    final d = await db;
    final now = DateTime.now();
    if (monthIdx < now.year * 12 + now.month - 1) return [];
    final out = <Pend>[];
    for (final r in await recs()) {
      if (monthIdx < r.start) continue;
      if (r.total != null && monthIdx - r.start + 1 > r.total!) continue;
      if (await _covered(d, r, monthIdx)) continue;
      out.add(Pend(r, monthIdx, r.dueDate(monthIdx)));
    }
    out.sort((a, b) => a.due.compareTo(b.due));
    return out;
  }

  static Future<void> payRec(Pend p) async =>
      _insertRec(await db, p.rec, p.idx, DateTime.now().millisecondsSinceEpoch);
}
