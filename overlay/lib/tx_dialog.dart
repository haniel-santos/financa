import 'package:flutter/material.dart';
import 'cat.dart';
import 'db.dart';
import 'parser.dart';

/// Diálogo de lançamento manual (banco ou dinheiro físico). Retorna true se salvou.
Future<bool> addTxDialog(BuildContext context, List<Cat> cats,
    {bool cash = false, bool income = false}) async {
  final valor = TextEditingController(), desc = TextEditingController();
  var inc = income, isCash = cash;
  var catSel = 'Outros';
  final choices = cats.where((c) => c.name != 'Renda').toList();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(isCash ? (inc ? 'Entrada em dinheiro' : 'Gasto em dinheiro') : 'Novo lançamento'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: valor, keyboardType: TextInputType.number, autofocus: true,
                decoration: const InputDecoration(labelText: 'Valor (ex: 25,90)')),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descrição')),
            if (!inc)
              DropdownButton<String>(
                isExpanded: true,
                value: catSel,
                items: [for (final cc in choices) DropdownMenuItem(value: cc.name, child: Text(cc.name))],
                onChanged: (v) => set(() => catSel = v ?? catSel),
              ),
            SwitchListTile(title: const Text('Entrada'), value: inc, onChanged: (v) => set(() => inc = v)),
            SwitchListTile(
                title: const Text('Dinheiro (espécie)'),
                value: isCash,
                onChanged: (v) => set(() => isCash = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    ),
  );
  final v = parseMoney(valor.text);
  if (ok != true || v == null || v <= 0) return false;
  final now = DateTime.now().millisecondsSinceEpoch;
  await DB.insert(
    Tx(
      amount: v,
      income: inc,
      merchant: desc.text.trim().isEmpty ? (isCash ? 'Dinheiro' : 'Manual') : desc.text.trim(),
      category: 'Outros',
      ts: now,
      raw: 'manual|$now|${desc.text}|$v',
      cash: isCash,
    ),
    category: inc ? 'Renda' : catSel,
  );
  return true;
}
