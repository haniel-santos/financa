import 'package:flutter/material.dart';
import 'parser.dart';

const iconMap = <String, IconData>{
  'restaurant': Icons.restaurant, 'directions_car': Icons.directions_car, 'home': Icons.home,
  'favorite': Icons.favorite, 'sports_esports': Icons.sports_esports, 'shopping_bag': Icons.shopping_bag,
  'subscriptions': Icons.subscriptions, 'attach_money': Icons.attach_money, 'category': Icons.category,
  'school': Icons.school, 'pets': Icons.pets, 'flight': Icons.flight, 'fitness_center': Icons.fitness_center,
  'local_gas_station': Icons.local_gas_station, 'phone_android': Icons.phone_android, 'savings': Icons.savings,
  'work': Icons.work, 'child_care': Icons.child_care, 'local_cafe': Icons.local_cafe, 'build': Icons.build,
  'card_giftcard': Icons.card_giftcard, 'wifi': Icons.wifi, 'movie': Icons.movie, 'checkroom': Icons.checkroom,
};

const palette = [
  0xFFEF6C00, 0xFF1E88E5, 0xFF6D4C41, 0xFFE53935, 0xFF8E24AA, 0xFFD81B60,
  0xFF00897B, 0xFF43A047, 0xFF757575, 0xFFFDD835, 0xFF3949AB, 0xFF00ACC1,
];

// Não podem ser excluídas nem renomeadas.
const protectedCats = {'Renda', 'Outros'};

class Cat {
  final String name;
  final String icon;
  final int color;
  final double? limit; // limite mensal de gastos (opcional)
  Cat(this.name, this.icon, this.color, this.limit);
  Color get colorV => Color(color);
  IconData get iconV => iconMap[icon] ?? Icons.category;
}

Future<Cat?> showCatDialog(BuildContext context, {Cat? cat}) {
  final name = TextEditingController(text: cat?.name ?? '');
  final limit = TextEditingController(
      text: cat?.limit == null ? '' : cat!.limit!.toStringAsFixed(2).replaceAll('.', ','));
  var icon = cat?.icon ?? 'category';
  var color = cat?.color ?? palette[0];
  final locked = cat != null && protectedCats.contains(cat.name);
  return showDialog<Cat>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(cat == null ? 'Nova categoria' : 'Editar categoria'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: name, enabled: !locked, decoration: const InputDecoration(labelText: 'Nome')),
              if (cat?.name != 'Renda')
                TextField(controller: limit, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Limite mensal (opcional)')),
              const SizedBox(height: 16),
              const Text('Ícone'),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final e in iconMap.entries)
                  IconButton(
                    icon: Icon(e.value),
                    style: IconButton.styleFrom(
                        backgroundColor: icon == e.key ? scheme.primaryContainer : null),
                    onPressed: () => set(() => icon = e.key),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Cor'),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => set(() => color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: color == c ? Border.all(width: 3, color: scheme.onSurface) : null,
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final n = locked ? cat!.name : name.text.trim();
                if (n.isEmpty) return;
                final lv = parseMoney(limit.text);
                Navigator.pop(ctx, Cat(n, icon, color, (lv != null && lv > 0) ? lv : null));
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    ),
  );
}
