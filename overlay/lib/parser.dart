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

const categories = ['Alimentação', 'Transporte', 'Moradia', 'Saúde', 'Lazer',
  'Compras', 'Assinaturas', 'Renda', 'Outros'];

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

String norm(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  var r = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    r = r.replaceAll(from[i].toLowerCase(), to[i].toLowerCase());
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
