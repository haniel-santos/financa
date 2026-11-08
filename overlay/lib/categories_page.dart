import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'cat.dart';
import 'db.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<Cat> cats = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    cats = await DB.cats();
    if (mounted) setState(() {});
  }

  void snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> add() async {
    final c = await showCatDialog(context);
    if (c == null || !mounted) return;
    if (!await DB.addCat(c)) {
      if (mounted) snack('Já existe uma categoria com esse nome');
      return;
    }
    load();
  }

  Future<void> edit(Cat old) async {
    final c = await showCatDialog(context, cat: old);
    if (c == null || !mounted) return;
    if (c.name != old.name && cats.any((x) => x.name == c.name)) {
      snack('Já existe uma categoria com esse nome');
      return;
    }
    await DB.updateCat(old.name, c);
    load();
  }

  Future<void> remove(Cat c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "${c.name}"?'),
        content: const Text('Os lançamentos dessa categoria vão para "Outros".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await DB.deleteCat(c.name);
      load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: add, icon: const Icon(Icons.add), label: const Text('Nova categoria')),
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        for (final c in cats)
          ListTile(
            leading: CircleAvatar(backgroundColor: c.colorV, child: Icon(c.iconV, color: Colors.white)),
            title: Text(c.name),
            subtitle: c.limit == null ? null : Text('Limite mensal ${money.format(c.limit)}'),
            trailing: protectedCats.contains(c.name)
                ? null
                : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => remove(c)),
            onTap: () => edit(c),
          ),
      ]),
    );
  }
}
