import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'db.dart';
import 'parser.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Finanças',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const Home(),
      );
}

const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  static const ch = MethodChannel('fin/notifications');
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<Tx> txs = [];
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

  Future<void> sync() async {
    access = await ch.invokeMethod<bool>('hasAccess') ?? false;
    final raw = await ch.invokeMethod<String>('drain') ?? '[]';
    for (final n in jsonDecode(raw)) {
      final t = parseNotification(n['title'] ?? '', n['text'] ?? '', n['ts'] as int);
      if (t != null) await DB.insert(t);
    }
    txs = await DB.month(month);
    if (mounted) setState(() {});
  }

  void move(int d) {
    month = DateTime(month.year, month.month + d);
    sync();
  }

  Future<void> pickCategory(Tx t) async {
    final cat = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(children: [
        for (final c in categories) ListTile(title: Text(c), onTap: () => Navigator.pop(context, c)),
      ]),
    );
    if (cat != null) {
      await DB.setCategory(t, cat);
      sync();
    }
  }

  Future<void> addManual() async {
    final valor = TextEditingController(), desc = TextEditingController();
    var income = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Novo lançamento'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: valor, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor (ex: 25,90)')),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descrição')),
            SwitchListTile(title: const Text('Entrada'), value: income, onChanged: (v) => set(() => income = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = double.tryParse(valor.text.replaceAll('.', '').replaceAll(',', '.'));
    if (ok == true && v != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await DB.insert(Tx(amount: v, income: income, merchant: desc.text.isEmpty ? 'Manual' : desc.text,
          category: 'Outros', ts: now, raw: 'manual|$now|${desc.text}|$v'));
      sync();
    }
  }

  @override
  Widget build(BuildContext c) {
    final inc = txs.where((t) => t.income).fold(0.0, (a, t) => a + t.amount);
    final out = txs.where((t) => !t.income).fold(0.0, (a, t) => a + t.amount);
    final byCat = <String, double>{};
    for (final t in txs.where((t) => !t.income)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: () => move(-1), icon: const Icon(Icons.chevron_left)),
          Text('${_meses[month.month - 1]} ${month.year}'),
          IconButton(onPressed: () => move(1), icon: const Icon(Icons.chevron_right)),
        ]),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(onPressed: addManual, child: const Icon(Icons.add)),
      body: RefreshIndicator(
        onRefresh: sync,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!access)
            Card(
              color: Colors.amber.shade100,
              child: ListTile(
                title: const Text('Ative o acesso às notificações'),
                subtitle: const Text('Necessário para lançar os gastos automaticamente.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ch.invokeMethod('openSettings'),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Saldo do mês'),
                Text(money.format(inc - out),
                    style: Theme.of(c).textTheme.headlineMedium?.copyWith(
                        color: inc - out >= 0 ? Colors.teal : Colors.red)),
                const SizedBox(height: 8),
                Text('Entradas ${money.format(inc)}   •   Saídas ${money.format(out)}'),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          for (final e in cats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(e.key), Text(money.format(e.value))]),
                LinearProgressIndicator(value: out == 0 ? 0 : e.value / out),
              ]),
            ),
          const Divider(height: 32),
          for (final t in txs)
            Dismissible(
              key: ValueKey(t.id),
              onDismissed: (_) async {
                await DB.delete(t);
                sync();
              },
              child: ListTile(
                title: Text(t.merchant),
                subtitle: Text('${t.category} • ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t.ts))}'),
                trailing: Text((t.income ? '+ ' : '- ') + money.format(t.amount),
                    style: TextStyle(color: t.income ? Colors.teal : Colors.red)),
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
