class Tx {
  int? id;
  final double amount;
  final bool income;
  final String merchant;
  String category;
  final int ts;
  final String raw;
  Tx({this.id, required this.amount, required this.income, required this.merchant,
      required this.category, required this.ts, required this.raw});
}

class SeedCat {
  final String name, icon;
  final int color;
  const SeedCat(this.name, this.icon, this.color);
}

// Categorias iniciais (você pode editar, excluir e criar novas dentro do app).
const seedCats = [
  SeedCat('Alimentação', 'restaurant', 0xFFEF6C00),
  SeedCat('Transporte', 'directions_car', 0xFF1E88E5),
  SeedCat('Moradia', 'home', 0xFF6D4C41),
  SeedCat('Saúde', 'favorite', 0xFFE53935),
  SeedCat('Lazer', 'sports_esports', 0xFF8E24AA),
  SeedCat('Compras', 'shopping_bag', 0xFFD81B60),
  SeedCat('Assinaturas', 'subscriptions', 0xFF00897B),
  SeedCat('Renda', 'attach_money', 0xFF43A047),
  SeedCat('Outros', 'category', 0xFF757575),
];

// Regras padrão (palavra-chave -> categoria). O app aprende as suas ao corrigir.
const defaultRules = {
  'ifood': 'Alimentação', 'padaria': 'Alimentação', 'mercado': 'Alimentação',
  'restaurante': 'Alimentação', 'lanchonete': 'Alimentação', 'acai': 'Alimentação',
  'uber': 'Transporte', 'posto': 'Transporte', 'combustivel': 'Transporte',
  'farmacia': 'Saúde', 'drogaria': 'Saúde',
  'netflix': 'Assinaturas', 'spotify': 'Assinaturas', 'youtube': 'Assinaturas',
  'shopee': 'Compras', 'amazon': 'Compras', 'mercado livre': 'Compras',
  'energia': 'Moradia', 'agua': 'Moradia', 'aluguel': 'Moradia', 'internet': 'Moradia',
  'cinema': 'Lazer', 'bar ': 'Lazer',
};

double? parseMoney(String s) {
  s = s.trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

String norm(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  var r = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    r = r.replaceAll(from[i], to[i]);
  }
  return r;
}

/// Converte o texto de uma notificação bancária em lançamento. Retorna null se não for transação.
Tx? parseNotification(String title, String text, int ts) {
  final full = '$title $text';
  final m = RegExp(r'R\$\s?([\d\.]+,\d{2})').firstMatch(full);
  if (m == null) return null;
  final amount = double.parse(m.group(1)!.replaceAll('.', '').replaceAll(',', '.'));
  final low = norm(full);

  final income = RegExp(r'recebeu|recebido|recebida|deposito|estorno|reembolso|salario|te enviou|enviou .* para voce')
      .hasMatch(low);
  final expense = RegExp(r'compra|pagamento|voce pagou|pagou|enviou|enviado|debito|transferencia')
      .hasMatch(low);
  if (!income && !expense) return null;

  final mm = RegExp(r'(?:\bem|\bno|\bna|\bpara)\s+([A-Za-zÀ-ú0-9 \*\.&\-]{2,30}?)(?:\s+(?:foi|no valor|com final)|[\.,!]|$)',
          caseSensitive: false).firstMatch(text);
  final merchant = (mm?.group(1) ?? title).trim();

  return Tx(amount: amount, income: income, merchant: merchant,
      category: income ? 'Renda' : 'Outros', ts: ts, raw: full);
}
