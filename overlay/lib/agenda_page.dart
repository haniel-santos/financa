import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'cat.dart';
import 'db.dart';
import 'parser.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({super.key});
  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<Rec> recs = [];
  List<Cat> cats = [];
  Map<int, int> counts = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    recs = await DB.recs();
    cats = await DB.cats();
    counts = await DB.recCounts();
    if (mounted) setState(() {});
  }

  Cat catOf(String n) =>
      cats.firstWhere((c) => c.name == n, orElse: () => Cat(n, 'category', 0xFF757575, null));

  void snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> add() async {
    final name = TextEditingController(), valor = TextEditingController();
    final dia = TextEditingController(text: DateTime.now().day.toString());
    final parc = TextEditingController();
    var income = false, auto = true, next = false;
    var catSel = 'Outros';
    final choices = cats.where((c) => c.name != 'Renda').toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nova conta agendada'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (ex: Aluguel)')),
              TextField(controller: valor, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor (ex: 800,00)')),
              TextField(controller: dia, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dia do mês (1 a 31)')),
              TextField(controller: parc, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Parcelas (vazio = todo mês, sem fim)')),
              if (!income)
                DropdownButton<String>(
                  isExpanded: true,
                  value: catSel,
                  items: [for (final cc in choices) DropdownMenuItem(value: cc.name, child: Text(cc.name))],
                  onChanged: (v) => set(() => catSel = v ?? catSel),
                ),
              SwitchListTile(
                  title: const Text('Entrada (receita fixa)'),
                  value: income,
                  onChanged: (v) => set(() => income = v)),
              SwitchListTile(
                  title: const Text('Lançar automaticamente'),
                  subtitle: const Text('Desligado: só aparece como lembrete'),
                  value: auto,
                  onChanged: (v) => set(() => auto = v)),
              SwitchListTile(
                  title: const Text('Começar no próximo mês'),
                  value: next,
                  onChanged: (v) => set(() => next = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final v = parseMoney(valor.text);
    final day = int.tryParse(dia.text.trim());
    final parcTxt = parc.text.trim();
    final total = parcTxt.isEmpty ? null : int.tryParse(parcTxt);
    final n = name.text.trim();
    if (n.isEmpty || v == null || v <= 0 || day == null || day < 1 || day > 31 ||
        (parcTxt.isNotEmpty && (total == null || total < 1))) {
      snack('Confira nome, valor, dia (1 a 31) e parcelas');
      return;
    }
    final now = DateTime.now();
    final start = now.year * 12 + now.month - 1 + (next ? 1 : 0);
    await DB.addRec(Rec(0, n, v, day, income ? 'Renda' : catSel, income, auto, start, total));
    load();
  }

  Future<void> remove(Rec r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "${r.name}"?'),
        content: const Text('Os lançamentos já feitos continuam no histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await DB.deleteRec(r.id);
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contas agendadas')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: add, icon: const Icon(Icons.add), label: const Text('Nova conta')),
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Contas fixas e parcelas entram sozinhas no dia marcado. '
              'Se o banco avisar o mesmo valor perto da data, o app não duplica.'),
        ),
        for (final r in recs)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: catOf(r.category).colorV,
              child: Icon(catOf(r.category).iconV, color: Colors.white),
            ),
            title: Text(r.name),
            subtitle: Text('${r.income ? 'Entrada' : 'Saída'} • dia ${r.day}'
                '${r.auto ? ' • automática' : ' • lembrete'}'
                '${r.total != null ? ' • ${counts[r.id] ?? 0}/${r.total} lançadas' : ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money.format(r.amount)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => remove(r)),
            ]),
          ),
        if (recs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nenhuma conta agendada. Adicione aluguel, internet, parcelas...')),
          ),
      ]),
    );
  }
}
