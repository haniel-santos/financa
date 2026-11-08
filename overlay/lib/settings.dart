import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'categories_page.dart';
import 'db.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

class SettingsPage extends StatefulWidget {
  final DateTime month;
  const SettingsPage({super.key, required this.month});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const ch = MethodChannel('fin/notifications');

  Future<void> setTheme(ThemeMode m) async {
    themeMode.value = m;
    await DB.setSetting('theme', m == ThemeMode.dark ? 'dark' : (m == ThemeMode.light ? 'light' : 'system'));
    if (mounted) setState(() {});
  }

  Future<void> exportCsv() async {
    final txs = await DB.month(widget.month);
    final f = DateFormat('yyyy-MM-dd HH:mm');
    final b = StringBuffer('data,tipo,descricao,categoria,valor\n');
    for (final t in txs.reversed) {
      b.writeln('${f.format(DateTime.fromMillisecondsSinceEpoch(t.ts))},'
          '${t.income ? 'entrada' : 'saida'},'
          '"${t.merchant.replaceAll('"', '""')}","${t.category}",${t.amount.toStringAsFixed(2)}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV do mês copiado! Cole no Google Sheets, Excel ou WhatsApp.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Tema'),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
            ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode)),
          ],
          selected: {themeMode.value},
          onSelectionChanged: (s) => setTheme(s.first),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.category),
          title: const Text('Categorias'),
          subtitle: const Text('Criar, editar, definir limites mensais'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesPage())),
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Exportar mês (CSV)'),
          subtitle: const Text('Copia os lançamentos do mês exibido'),
          onTap: exportCsv,
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Acesso às notificações'),
          subtitle: const Text('Abre a tela do Android para ativar/desativar'),
          onTap: () => ch.invokeMethod('openSettings'),
        ),
      ]),
    );
  }
}
