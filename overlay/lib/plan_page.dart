import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'agenda_page.dart';
import 'cat.dart';
import 'db.dart';
import 'goals.dart';
import 'parser.dart';
import 'tx_dialog.dart';

const _pos = Color(0xFF26A69A);
const _neg = Color(0xFFEF5350);
const _meses = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

class PlanPage extends StatefulWidget {
  final DateTime month;
  const PlanPage({super.key, required this.month});
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  bool loading = true;
  double baseIncome = 0;
  bool savePct = true;
  double saveVal = 10;
  double cashStart = 0;
  double actualIn = 0, out = 0, cashMonth = 0, saved = 0, cashBalance = 0, recIncome = 0;
  List<FixedItem> fixed = [];
  List<Cat> cats = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final m = widget.month;
    final idx = m.year * 12 + m.month - 1;
    baseIncome = double.tryParse(await DB.getSetting('plan_income') ?? '') ?? 0;
    savePct = (await DB.getSetting('plan_save_mode') ?? 'pct') == 'pct';
    saveVal = double.tryParse(await DB.getSetting('plan_save') ?? '') ?? 10;
    cashStart = double.tryParse(await DB.getSetting('cash_start') ?? '') ?? 0;
    final txs = await DB.month(DateTime(m.year, m.month));
    actualIn = txs.where((t) => t.income).fold(0.0, (a, t) => a + t.amount);
    out = txs.where((t) => !t.income).fold(0.0, (a, t) => a + t.amount);
    cashMonth = txs.where((t) => !t.income && t.cash).fold(0.0, (a, t) => a + t.amount);
    fixed = await DB.fixedForMonth(idx);
    final recs = await DB.recs();
    recIncome = recs
        .where((r) => r.income && idx >= r.start && (r.total == null || idx - r.start + 1 <= r.total!))
        .fold(0.0, (a, r) => a + r.amount);
    saved = await DB.depositsSum(DateTime(m.year, m.month));
    cashBalance = cashStart + await DB.cashDelta();
    cats = await DB.cats();
    if (mounted) setState(() => loading = false);
  }

  double get planned => baseIncome > 0 ? baseIncome : recIncome;
  double get renda => planned > 0 ? (actualIn > planned ? actualIn : planned) : actualIn;
  double get fixedTotal => fixed.fold(0.0, (a, f) => a + f.rec.amount);
  double get fixedPaid => fixed.where((f) => f.paid).fold(0.0, (a, f) => a + f.rec.amount);
  double get saveTarget => savePct ? renda * saveVal / 100 : saveVal;
  double get canSpend => renda - fixedTotal - saveTarget;
  double get varSpent => (out - fixedPaid).clamp(0, double.infinity).toDouble();
  double get remaining => canSpend - varSpent;

  int get daysLeft {
    final now = DateTime.now();
    final m = widget.month;
    final dim = DateTime(m.year, m.month + 1, 0).day;
    final cur = m.year * 12 + m.month, nowI = now.year * 12 + now.month;
    if (cur == nowI) return dim - now.day + 1;
    return cur > nowI ? dim : 0;
  }

  Future<void> editIncome() async {
    final c = TextEditingController(
        text: baseIncome > 0 ? baseIncome.toStringAsFixed(2).replaceAll('.', ',') : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renda mensal'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c, keyboardType: TextInputType.number, autofocus: true,
              decoration: const InputDecoration(labelText: 'Quanto você recebe por mês (ex: 2500,00)')),
          const SizedBox(height: 8),
          const Text('Deixe vazio para usar o que entrou de fato no mês.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true) {
      await DB.setSetting('plan_income', (parseMoney(c.text) ?? 0).toString());
      load();
    }
  }

  Future<void> editSave() async {
    var pct = savePct;
    final c = TextEditingController(
        text: saveVal.toStringAsFixed(saveVal == saveVal.roundToDouble() ? 0 : 2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Quanto guardar por mês'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('% da renda')),
                ButtonSegment(value: false, label: Text('Valor fixo')),
              ],
              selected: {pct},
              onSelectionChanged: (s) => set(() => pct = s.first),
            ),
            TextField(controller: c, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: pct ? 'Percentual (ex: 10)' : 'Valor (ex: 300,00)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = parseMoney(c.text);
    if (ok == true && v != null && v >= 0) {
      await DB.setSetting('plan_save_mode', pct ? 'pct' : 'val');
      await DB.setSetting('plan_save', v.toString());
      load();
    }
  }

  Future<void> editCashStart() async {
    final c = TextEditingController(
        text: cashStart != 0 ? cashStart.toStringAsFixed(2).replaceAll('.', ',') : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dinheiro que você já tem'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true,
            decoration: const InputDecoration(labelText: 'Saldo inicial da carteira (ex: 150,00)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true) {
      await DB.setSetting('cash_start', (parseMoney(c.text) ?? 0).toString());
      load();
    }
  }

  Widget row(String label, String value, {VoidCallback? onTap, Color? color, bool bold = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Text(label, style: st)),
          Text(value, style: st.copyWith(color: color)),
          if (onTap != null)
            const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.edit, size: 16)),
        ]),
      ),
    );
  }

  Widget card(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rem = remaining;
    final per = daysLeft > 0 && rem > 0 ? rem / daysLeft : 0.0;
    final spentRatio = canSpend <= 0
        ? (varSpent > 0 ? 1.0 : 0.0)
        : (varSpent / canSpend).clamp(0.0, 1.0).toDouble();
    final saveRatio = saveTarget <= 0 ? 0.0 : (saved / saveTarget).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(title: Text('Planejamento • ${_meses[widget.month.month - 1]}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (renda <= 0)
                Card(
                  color: cs.tertiaryContainer,
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: cs.onTertiaryContainer),
                    title: Text('Informe sua renda mensal para começar',
                        style: TextStyle(color: cs.onTertiaryContainer)),
                    onTap: editIncome,
                  ),
                ),
              card([
                Text('Como fica o mês', style: tt.titleMedium),
                row('Renda do mês', money.format(renda), onTap: editIncome, color: _pos),
                row('− Contas fixas', money.format(fixedTotal)),
                row('− Guardar (${savePct ? '${saveVal.toStringAsFixed(0)}%' : 'valor fixo'})',
                    money.format(saveTarget), onTap: editSave),
                const Divider(),
                row('= Pode gastar', money.format(canSpend),
                    bold: true, color: canSpend < 0 ? _neg : null),
              ]),
              card([
                Text('Quanto ainda pode gastar', style: tt.titleMedium),
                const SizedBox(height: 8),
                Text(money.format(rem < 0 ? -rem : rem),
                    style: tt.headlineMedium?.copyWith(color: rem >= 0 ? _pos : _neg)),
                Text(rem >= 0 ? 'ainda disponível para gastos do dia a dia' : 'acima do que dava para gastar'),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: spentRatio,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: rem < 0 ? _neg : (spentRatio >= 0.8 ? Colors.orange : _pos),
                ),
                const SizedBox(height: 8),
                Text('Gasto do dia a dia: ${money.format(varSpent)} de ${money.format(canSpend < 0 ? 0 : canSpend)}'),
                if (per > 0)
                  Text('Dá ${money.format(per)} por dia (restam $daysLeft dias)',
                      style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
              card([
                Text('Guardar', style: tt.titleMedium),
                const SizedBox(height: 8),
                Text('Guardado neste mês: ${money.format(saved)} de ${money.format(saveTarget)}'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: saveRatio, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.savings),
                  label: const Text('Guardar nas metas'),
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => GoalsPage(sobra: rem > 0 ? rem : 0)));
                    load();
                  },
                ),
              ]),
              card([
                Row(children: [
                  Expanded(child: Text('Dinheiro físico (carteira)', style: tt.titleMedium)),
                  IconButton(
                      tooltip: 'Saldo inicial', icon: const Icon(Icons.edit, size: 18), onPressed: editCashStart),
                ]),
                Text(money.format(cashBalance),
                    style: tt.headlineSmall?.copyWith(color: cashBalance >= 0 ? _pos : _neg)),
                Text('Gasto em dinheiro neste mês: ${money.format(cashMonth)}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.remove),
                    label: const Text('Gasto'),
                    onPressed: () async {
                      if (await addTxDialog(context, cats, cash: true)) load();
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Entrada'),
                    onPressed: () async {
                      if (await addTxDialog(context, cats, cash: true, income: true)) load();
                    },
                  ),
                ]),
              ]),
              card([
                Row(children: [
                  Expanded(child: Text('Contas fixas do mês', style: tt.titleMedium)),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const AgendaPage()));
                      load();
                    },
                    child: const Text('Gerenciar'),
                  ),
                ]),
                if (fixed.isEmpty)
                  const Text('Nenhuma conta fixa. Cadastre aluguel, internet e parcelas em "Gerenciar".'),
                for (final f in fixed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(f.paid ? Icons.check_circle : Icons.schedule,
                        color: f.paid ? _pos : cs.onSurfaceVariant),
                    title: Text(f.rec.name),
                    subtitle: Text('dia ${f.rec.day} • ${f.paid ? 'pago' : 'pendente'}'),
                    trailing: Text(money.format(f.rec.amount)),
                  ),
              ]),
              const SizedBox(height: 24),
            ]),
    );
  }
}
