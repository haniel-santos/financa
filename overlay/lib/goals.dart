import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';

class GoalsPage extends StatefulWidget {
  final double sobra; // saldo do mês atual (entradas - saídas)
  const GoalsPage({super.key, required this.sobra});
  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<Goal> goals = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    goals = await DB.goals();
    if (mounted) setState(() {});
  }

  double? _parse(String s) {
    s = s.trim();
    if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(s);
  }

  Future<void> newGoal() async {
    final name = TextEditingController(), target = TextEditingController();
    DateTime? deadline;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nova meta'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (ex: Notebook)')),
            TextField(controller: target, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor da meta (ex: 3000,00)')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().add(const Duration(days: 180)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (d != null) set(() => deadline = d);
              },
              child: Text(deadline == null ? 'Prazo (opcional)' : DateFormat('dd/MM/yyyy').format(deadline!)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
          ],
        ),
      ),
    );
    final v = _parse(target.text);
    if (ok == true && v != null && v > 0 && name.text.trim().isNotEmpty) {
      await DB.addGoal(name.text.trim(), v, deadline);
      load();
    }
  }

  Future<void> move(Goal g, {required bool deposit, double? preset}) async {
    final c = TextEditingController(
        text: preset == null ? '' : preset.toStringAsFixed(2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deposit ? 'Guardar em ${g.name}' : 'Retirar de ${g.name}'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true,
            decoration: const InputDecoration(labelText: 'Valor (ex: 150,00)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    final v = _parse(c.text);
    if (ok == true && v != null && v > 0) {
      await DB.addToGoal(g.id, deposit ? v : -v);
      load();
    }
  }

  /// Quanto guardar por mês para chegar no prazo.
  double? perMonth(Goal g) {
    if (g.deadline == null) return null;
    final now = DateTime.now();
    final end = DateTime.fromMillisecondsSinceEpoch(g.deadline!);
    final months = ((end.year - now.year) * 12 + end.month - now.month).clamp(1, 1200);
    final falta = g.target - g.saved;
    return falta <= 0 ? 0 : falta / months;
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      appBar: AppBar(title: const Text('Metas')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: newGoal, icon: const Icon(Icons.add), label: const Text('Nova meta')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.sobra > 0 && goals.isNotEmpty)
          Card(
            color: Theme.of(c).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: Text('Sobrou ${money.format(widget.sobra)} neste mês'),
              subtitle: const Text('Que tal guardar uma parte numa meta?'),
            ),
          ),
        for (final g in goals)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(g.name, style: Theme.of(c).textTheme.titleMedium)),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'retirar') move(g, deposit: false);
                      if (v == 'excluir') {
                        await DB.deleteGoal(g.id);
                        load();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'retirar', child: Text('Retirar valor')),
                      PopupMenuItem(value: 'excluir', child: Text('Excluir meta')),
                    ],
                  ),
                ]),
                LinearProgressIndicator(value: g.pct, minHeight: 8),
                const SizedBox(height: 8),
                Text('${money.format(g.saved)} de ${money.format(g.target)} (${(g.pct * 100).toStringAsFixed(0)}%)'),
                if (g.saved >= g.target)
                  const Text('🎉 Meta atingida!')
                else if (perMonth(g) != null)
                  Text('Guarde ${money.format(perMonth(g))}/mês até '
                      '${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(g.deadline!))}'),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton.tonal(onPressed: () => move(g, deposit: true), child: const Text('Guardar')),
                  if (widget.sobra > 0 && g.saved < g.target) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => move(g, deposit: true,
                          preset: widget.sobra < g.target - g.saved ? widget.sobra : g.target - g.saved),
                      child: const Text('Usar a sobra'),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        if (goals.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Crie sua primeira meta (viagem, notebook, reserva de emergência...).')),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }
}
