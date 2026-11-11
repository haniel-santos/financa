import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'advisor_page.dart';
import 'agenda_page.dart';
import 'cat.dart';
import 'db.dart';
import 'goals.dart';
import 'parser.dart';
import 'plan_page.dart';
import 'settings.dart';
import 'tx_dialog.dart';

const posColor = Color(0xFF26A69A);
const negColor = Color(0xFFEF5350);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = await DB.getSetting('theme');
  themeMode.value = s == 'dark'
      ? ThemeMode.dark
      : (s == 'light' ? ThemeMode.light : ThemeMode.system);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'Finanças',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
          darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
          themeMode: mode,
          home: const Home(),
        ),
      );
}

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

class DonutPainter extends CustomPainter {
  final List<MapEntry<Color, double>> parts;
  final Color empty;
  DonutPainter(this.parts, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold(0.0, (a, e) => a + e.value);
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - 12);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;
    if (total <= 0) {
      p.color = empty;
      canvas.drawArc(rect, 0, 2 * pi, false, p);
      return;
    }
    var start = -pi / 2;
    for (final e in parts) {
      final sweep = e.value / total * 2 * pi;
      p.color = e.key;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter old) => true;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  static const ch = MethodChannel('fin/notifications');
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<Tx> txs = [];
  List<Cat> cats = [];
  Map<String, Cat> catMap = {};
  List<Pend> pending = [];
  bool access = true;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) sync();
  }

  Cat catOf(String name) => catMap[name] ?? Cat(name, 'category', 0xFF757575, null);

  void snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> sync() async {
    access = await ch.invokeMethod<bool>('hasAccess') ?? false;
    final raw = await ch.invokeMethod<String>('drain') ?? '[]';
    for (final n in jsonDecode(raw)) {
      final t = parseNotification(n['title'] ?? '', n['text'] ?? '', n['ts'] as int);
      if (t != null) await DB.insert(t);
    }
    await DB.generateDue();
    cats = await DB.cats();
    catMap = {for (final c in cats) c.name: c};
    txs = await DB.month(month);
    pending = await DB.pending(month.year * 12 + month.month - 1);
    if (mounted) setState(() {});
  }

  void move(int d) {
    month = DateTime(month.year, month.month + d);
    sync();
  }

  Future<void> pickCategory(Tx t) async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final cat in cats)
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: cat.colorV, child: Icon(cat.iconV, color: Colors.white, size: 18)),
              title: Text(cat.name),
              onTap: () => Navigator.pop(ctx, cat.name),
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Nova categoria...'),
            onTap: () => Navigator.pop(ctx, '__new__'),
          ),
        ]),
      ),
    );
    if (sel == null || !mounted) return;
    var name = sel;
    if (sel == '__new__') {
      final nc = await showCatDialog(context);
      if (nc == null || !mounted) return;
      if (!await DB.addCat(nc)) {
        if (mounted) snack('Já existe uma categoria com esse nome');
        return;
      }
      name = nc.name;
    }
    await DB.setCategory(t, name);
    sync();
  }

  Future<void> addManual() async {
    if (await addTxDialog(context, cats)) sync();
  }

  Widget catRow(String name, double v, double total, double? limit) {
    final cat = catOf(name);
    final lim = limit ?? 0.0;
    final hasLimit = lim > 0;
    final ratio = hasLimit ? v / lim : (total == 0 ? 0.0 : v / total);
    final color = hasLimit
        ? (ratio >= 1 ? negColor : (ratio >= 0.8 ? Colors.orange : cat.colorV))
        : cat.colorV;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 12, backgroundColor: cat.colorV, child: Icon(cat.iconV, size: 14, color: Colors.white)),
          const SizedBox(width: 8),
          Expanded(child: Text(name)),
          Text(hasLimit ? '${money.format(v)} / ${money.format(lim)}' : money.format(v)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0).toDouble(),
          color: color,
          backgroundColor: color.withOpacity(0.18),
          minHeight: 6,
          borderRadius: BorderRadius.circular(4),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final inc = txs.where((t) => t.income).fold(0.0, (a, t) => a + t.amount);
    final out = txs.where((t) => !t.income).fold(0.0, (a, t) => a + t.amount);
    final pendOut = pending.where((p) => !p.rec.income).fold(0.0, (a, p) => a + p.rec.amount);
    final pendIn = pending.where((p) => p.rec.income).fold(0.0, (a, p) => a + p.rec.amount);
    final byCat = <String, double>{};
    for (final t in txs.where((t) => !t.income)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final list = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final limits = <String, double>{
      for (final cc in cats)
        if (cc.limit != null) cc.name: cc.limit!
    };
    final alerts = <String>[];
    for (final e in list) {
      final l = limits[e.key];
      if (l == null || l <= 0) continue;
      final p = e.value / l;
      if (p >= 1) {
        alerts.add('${e.key}: passou do limite (${(p * 100).toStringAsFixed(0)}%)');
      } else if (p >= 0.8) {
        alerts.add('${e.key}: ${(p * 100).toStringAsFixed(0)}% do limite');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => move(-1), icon: const Icon(Icons.chevron_left)),
          Text('${_meses[month.month - 1]} ${month.year}'),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => move(1), icon: const Icon(Icons.chevron_right)),
        ]),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Metas',
            icon: const Icon(Icons.savings),
            onPressed: () => Navigator.push(
                c, MaterialPageRoute(builder: (_) => GoalsPage(sobra: inc - out))),
          ),
          IconButton(
            tooltip: 'Contas agendadas',
            icon: const Icon(Icons.event_repeat),
            onPressed: () async {
              await Navigator.push(c, MaterialPageRoute(builder: (_) => const AgendaPage()));
              sync();
            },
          ),
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(c, MaterialPageRoute(builder: (_) => SettingsPage(month: month)));
              sync();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: addManual, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: sync,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          Card(
            color: cs.primaryContainer,
            child: ListTile(
              leading: Icon(Icons.account_balance_wallet, color: cs.onPrimaryContainer),
              title: Text('Planejamento do mês',
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
              subtitle: Text('Renda, contas fixas, quanto guardar e quanto pode gastar',
                  style: TextStyle(color: cs.onPrimaryContainer)),
              trailing: Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
              onTap: () async {
                await Navigator.push(c, MaterialPageRoute(builder: (_) => PlanPage(month: month)));
                sync();
              },
            ),
          ),
          Card(
            color: cs.secondaryContainer,
            child: ListTile(
              leading: Icon(Icons.psychology, color: cs.onSecondaryContainer),
              title: Text('Conselheiro financeiro',
                  style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.bold)),
              subtitle: Text('Diagnóstico do mês e plano para atingir suas metas',
                  style: TextStyle(color: cs.onSecondaryContainer)),
              trailing: Icon(Icons.chevron_right, color: cs.onSecondaryContainer),
              onTap: () async {
                await Navigator.push(c, MaterialPageRoute(builder: (_) => const AdvisorPage()));
                sync();
              },
            ),
          ),
          if (!access)
            Card(
              color: cs.tertiaryContainer,
              child: ListTile(
                title: Text('Ative o acesso às notificações', style: TextStyle(color: cs.onTertiaryContainer)),
                subtitle: Text('Necessário para lançar os gastos automaticamente.',
                    style: TextStyle(color: cs.onTertiaryContainer)),
                trailing: Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
                onTap: () => ch.invokeMethod('openSettings'),
              ),
            ),
          if (alerts.isNotEmpty)
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final a in alerts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, size: 20, color: cs.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a, style: TextStyle(color: cs.onErrorContainer))),
                      ]),
                    ),
                ]),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Saldo do mês'),
                Text(money.format(inc - out),
                    style: Theme.of(c).textTheme.headlineMedium?.copyWith(
                        color: inc - out >= 0 ? posColor : negColor)),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.arrow_downward, size: 16, color: posColor),
                  Text(' ${money.format(inc)}'),
                  const SizedBox(width: 16),
                  Icon(Icons.arrow_upward, size: 16, color: negColor),
                  Text(' ${money.format(out)}'),
                ]),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Saldo previsto: ${money.format(inc - out - pendOut + pendIn)}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ]),
            ),
          ),
          if (pending.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.event_repeat, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Contas a vir neste mês', style: Theme.of(c).textTheme.titleSmall)),
                    Text(money.format(pendOut)),
                    const SizedBox(width: 8),
                  ]),
                  for (final p in pending.take(5))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: catOf(p.rec.category).colorV,
                        child: Icon(catOf(p.rec.category).iconV, size: 14, color: Colors.white),
                      ),
                      title: Text(p.rec.name),
                      subtitle: Text('dia ${p.due.day}${p.rec.auto ? ' • automática' : ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text((p.rec.income ? '+ ' : '- ') + money.format(p.rec.amount)),
                        if (!p.rec.auto)
                          IconButton(
                            tooltip: 'Marcar como paga',
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () async {
                              await DB.payRec(p);
                              sync();
                            },
                          ),
                      ]),
                    ),
                  if (pending.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('+ ${pending.length - 5} contas'),
                    ),
                ]),
              ),
            ),
          if (list.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: DonutPainter(
                      [for (final e in list) MapEntry(catOf(e.key).colorV, e.value)], cs.surfaceContainerHighest),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Gastos'),
                  Text(money.format(out), style: Theme.of(c).textTheme.titleLarge),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            for (final e in list) catRow(e.key, e.value, out, limits[e.key]),
          ],
          const Divider(height: 32),
          for (final t in txs)
            Dismissible(
              key: ValueKey(t.id),
              onDismissed: (_) async {
                await DB.delete(t);
                sync();
              },
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: catOf(t.category).colorV,
                  child: Icon(catOf(t.category).iconV, color: Colors.white, size: 20),
                ),
                title: Text(t.merchant),
                subtitle: Text('${t.category} • ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t.ts))}${t.cash ? ' • dinheiro' : ''}'),
                trailing: Text((t.income ? '+ ' : '- ') + money.format(t.amount),
                    style: TextStyle(color: t.income ? posColor : negColor)),
                onTap: () => pickCategory(t),
              ),
            ),
          if (txs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Sem lançamentos ainda. Faça uma compra e ela aparece aqui.')),
            ),
        ]),
      ),
    );
  }
}
