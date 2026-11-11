import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'cat.dart';
import 'db.dart';
import 'goals.dart';
import 'parser.dart';
import 'plan_page.dart';

const _pos = Color(0xFF26A69A);
const _neg = Color(0xFFEF5350);
const _warn = Color(0xFFFFA726);

class Diag {
  final int level; // 0 ok, 1 atenção, 2 problema
  final String title, text;
  Diag(this.level, this.title, this.text);
}

class AdvisorPage extends StatefulWidget {
  const AdvisorPage({super.key});
  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends State<AdvisorPage> {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  bool loading = true;
  double renda = 0, fixedTotal = 0, saveTarget = 0, saved = 0, varSpent = 0, out = 0;
  double baseVar = 0, capacity = 0, avgOut = 0;
  int histMonths = 0;
  Map<String, double> byCat = {}, avgByCat = {};
  List<Cat> cats = [];
  List<Goal> goals = [];
  Map<int, double> pace = {};
  List<Diag> diags = [];

  String m(double v) => money.format(v);
  String fmt(DateTime d) => DateFormat('MM/yyyy').format(d);
  String pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

  @override
  void initState() {
    super.initState();
    load();
  }

  bool isEmerg(Goal g) {
    final n = norm(g.name);
    return n.contains('emerg') || n.contains('reserv');
  }

  Future<void> load() async {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final idx = now.year * 12 + now.month - 1;
    final base = double.tryParse(await DB.getSetting('plan_income') ?? '') ?? 0;
    final savePct = (await DB.getSetting('plan_save_mode') ?? 'pct') == 'pct';
    final saveVal = double.tryParse(await DB.getSetting('plan_save') ?? '') ?? 10;

    final txs = await DB.month(month);
    final actualIn = txs.where((t) => t.income).fold(0.0, (a, t) => a + t.amount);
    out = txs.where((t) => !t.income).fold(0.0, (a, t) => a + t.amount);
    byCat = {};
    for (final t in txs.where((t) => !t.income)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final fixed = await DB.fixedForMonth(idx);
    fixedTotal = fixed.fold(0.0, (a, f) => a + f.rec.amount);
    final fixedPaid = fixed.where((f) => f.paid).fold(0.0, (a, f) => a + f.rec.amount);
    final recs = await DB.recs();
    final recIncome = recs
        .where((r) => r.income && idx >= r.start && (r.total == null || idx - r.start + 1 <= r.total!))
        .fold(0.0, (a, r) => a + r.amount);
    final planned = base > 0 ? base : recIncome;
    renda = planned > 0 ? (actualIn > planned ? actualIn : planned) : actualIn;
    saveTarget = savePct ? renda * saveVal / 100 : saveVal;
    saved = await DB.depositsSum(month);
    varSpent = (out - fixedPaid).clamp(0, double.infinity).toDouble();

    // Histórico: até 3 meses anteriores com dados.
    final sums = <String, double>{};
    var tot = 0.0;
    histMonths = 0;
    for (var i = 1; i <= 3; i++) {
      final h = await DB.month(DateTime(now.year, now.month - i));
      final ex = h.where((t) => !t.income).toList();
      if (ex.isEmpty) continue;
      histMonths++;
      for (final t in ex) {
        sums[t.category] = (sums[t.category] ?? 0) + t.amount;
        tot += t.amount;
      }
    }
    if (histMonths > 0) {
      avgByCat = sums.map((k, v) => MapEntry(k, v / histMonths));
      avgOut = tot / histMonths;
    } else {
      avgByCat = {};
      avgOut = 0;
    }
    baseVar = histMonths > 0 ? (avgOut - fixedTotal).clamp(0, double.infinity).toDouble() : varSpent;
    capacity = (renda - fixedTotal - baseVar).clamp(0, double.infinity).toDouble();

    cats = await DB.cats();
    goals = await DB.goals();
    final pm = <int, double>{};
    for (final g in goals) {
      pm[g.id] = await DB.goalPace(g);
    }
    pace = pm;
    diags = diagnose(now);
    if (mounted) setState(() => loading = false);
  }

  List<Diag> diagnose(DateTime now) {
    final d = <Diag>[];
    if (renda <= 0) {
      d.add(Diag(2, 'Renda não informada',
          'Informe sua renda mensal em Planejamento para eu calcular o resto.'));
      return d;
    }
    // Contas fixas
    if (fixedTotal == 0) {
      d.add(Diag(1, 'Sem contas fixas cadastradas',
          'Cadastre aluguel, internet e parcelas em Contas agendadas para o planejamento ficar preciso.'));
    } else {
      final s = fixedTotal / renda;
      if (s > 0.5) {
        d.add(Diag(2, 'Contas fixas pesadas',
            'Ocupam ${pct(s)} da renda. Uma referência comum é manter as necessidades em até ~50%.'));
      } else if (s > 0.35) {
        d.add(Diag(1, 'Contas fixas em atenção',
            'Ocupam ${pct(s)} da renda (referência comum: até ~50% para necessidades).'));
      } else {
        d.add(Diag(0, 'Contas fixas sob controle', 'Ocupam ${pct(s)} da renda.'));
      }
    }
    // Guardar
    final saveShare = saveTarget / renda;
    if (saveShare < 0.1) {
      d.add(Diag(1, 'Meta de guardar baixa',
          'Você planeja guardar ${pct(saveShare)} da renda. Muita gente usa 10% a 20% como ponto de partida.'));
    } else {
      d.add(Diag(0, 'Meta de guardar saudável', 'Você planeja guardar ${pct(saveShare)} da renda.'));
    }
    if (saveTarget > 0) {
      if (saved >= saveTarget) {
        d.add(Diag(0, 'Meta de guardar do mês batida', 'Guardado ${m(saved)} de ${m(saveTarget)}.'));
      } else {
        d.add(Diag(1, 'Falta guardar neste mês',
            'Guardado ${m(saved)} de ${m(saveTarget)}. Faltam ${m(saveTarget - saved)}.'));
      }
    }
    // Dia a dia
    final canSpend = renda - fixedTotal - saveTarget;
    if (canSpend <= 0) {
      d.add(Diag(2, 'Não sobra para o dia a dia',
          'Renda − fixas − guardar fica em ${m(canSpend)}. Reduza o valor a guardar ou as contas fixas.'));
    } else {
      final dim = DateTime(now.year, now.month + 1, 0).day;
      final expected = now.day / dim;
      final actual = varSpent / canSpend;
      if (actual >= 1) {
        d.add(Diag(2, 'Limite do dia a dia estourado',
            'Você já gastou ${m(varSpent)} e o limite era ${m(canSpend)}.'));
      } else if (actual > expected + 0.15) {
        d.add(Diag(1, 'Gastando mais rápido que o mês',
            'Já usou ${pct(actual)} do limite com ${pct(expected)} do mês passado.'));
      } else {
        d.add(Diag(0, 'Dia a dia no ritmo',
            'Usou ${pct(actual)} do limite com ${pct(expected)} do mês passado.'));
      }
    }
    // Limites por categoria
    for (final c in cats) {
      final l = c.limit;
      if (l == null || l <= 0) continue;
      final v = byCat[c.name] ?? 0;
      if (v >= l) {
        d.add(Diag(2, '${c.name} passou do limite', '${m(v)} de ${m(l)}.'));
      } else if (v >= 0.8 * l) {
        d.add(Diag(1, '${c.name} perto do limite', '${m(v)} de ${m(l)} (${pct(v / l)}).'));
      }
    }
    // Reserva de emergência
    final need = fixedTotal + baseVar;
    if (need > 0) {
      final em = goals.where(isEmerg).toList();
      if (em.isEmpty) {
        d.add(Diag(1, 'Sem reserva de emergência',
            'Uma referência comum é ter de 3 a 6 meses de gastos guardados: cerca de ${m(need * 3)} a ${m(need * 6)}.'));
      } else {
        final s = em.fold(0.0, (a, g) => a + g.saved);
        final months = s / need;
        if (months >= 3) {
          d.add(Diag(0, 'Reserva de emergência em dia', 'Cobre ${months.toStringAsFixed(1)} meses de gastos.'));
        } else {
          d.add(Diag(1, 'Reserva de emergência em construção',
              'Cobre ${months.toStringAsFixed(1)} meses. Referência comum: 3 a 6.'));
        }
      }
    }
    // Gastos sem categoria
    if (out > 0 && (byCat['Outros'] ?? 0) / out > 0.25) {
      d.add(Diag(1, 'Muitos gastos sem categoria',
          '${pct((byCat['Outros'] ?? 0) / out)} estão em "Outros". Toque nos lançamentos para categorizar; o app aprende.'));
    }
    // Maior alta frente à média
    if (histMonths > 0) {
      String? top;
      var topDiff = 0.0;
      for (final e in byCat.entries) {
        final a = avgByCat[e.key] ?? 0;
        final diff = e.value - a;
        if (a > 0 && e.value > a * 1.3 && diff > 30 && diff > topDiff) {
          top = e.key;
          topDiff = diff;
        }
      }
      if (top != null) {
        d.add(Diag(1, '$top acima da média',
            'Neste mês: ${m(byCat[top] ?? 0)} contra média de ${m(avgByCat[top] ?? 0)} nos meses anteriores.'));
      }
    }
    d.sort((a, b) => b.level.compareTo(a.level));
    return d;
  }

  List<String> cuts() {
    const keep = {'Moradia', 'Saúde', 'Transporte', 'Renda', 'Outros'};
    final src = histMonths > 0 ? avgByCat : byCat;
    final list = src.entries.where((e) => !keep.contains(e.key) && e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in list.take(2))
        'Reduzir ${e.key} em 20% libera ~${m(e.value * 0.2)}/mês (hoje ~${m(e.value)}).'
    ];
  }

  int cmp(Goal a, Goal b) {
    final fa = a.saved >= a.target, fb = b.saved >= b.target;
    if (fa != fb) return fa ? 1 : -1;
    final ea = isEmerg(a), eb = isEmerg(b);
    if (ea != eb) return ea ? -1 : 1;
    final da = a.deadline ?? 4611686018427387904;
    final dbb = b.deadline ?? 4611686018427387904;
    if (da != dbb) return da.compareTo(dbb);
    return (a.target - a.saved).compareTo(b.target - b.saved);
  }

  Widget t(String s, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(s, style: color == null ? null : TextStyle(color: color)),
      );

  Widget line(String a, String b, {bool bold = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Expanded(child: Text(a, style: st)), Text(b, style: st)]),
    );
  }

  Widget goalCard(Goal g, int rank) {
    final tt = Theme.of(context).textTheme;
    final rest = g.target - g.saved;
    final p = pace[g.id] ?? 0.0;
    final now = DateTime.now();
    final lines = <Widget>[];

    if (rest <= 0) {
      lines.add(t('🎉 Meta atingida! Parabéns.', color: _pos));
    } else if (g.deadline == null) {
      lines.add(t('Sem prazo definido. Defina uma data em Metas para eu calcular quanto guardar por mês.'));
      if (capacity > 0) {
        final mo = (rest / capacity).ceil();
        lines.add(t('Com a sobra estimada de ${m(capacity)}/mês, você chega lá em ~$mo meses (${fmt(DateTime(now.year, now.month + mo))}).'));
      } else {
        lines.add(t('Hoje não sobra dinheiro estimado no mês. Veja o diagnóstico acima.', color: _warn));
      }
    } else {
      final end = DateTime.fromMillisecondsSinceEpoch(g.deadline!);
      final days = end.difference(now).inDays;
      if (days <= 0) {
        lines.add(t('Prazo vencido. Ajuste a data ou o valor da meta.', color: _neg));
      } else {
        final months = (days / 30.4).clamp(1.0, 1200.0).toDouble();
        final perMonth = rest / months;
        lines.add(t('O que fazer: guarde ${m(perMonth)} por mês (≈ ${m(perMonth / 4.345)} por semana, ${m(perMonth / 30.4)} por dia) até ${DateFormat('dd/MM/yyyy').format(end)}.'));
        if (p >= perMonth) {
          lines.add(t('No ritmo: você guarda em média ${m(p)}/mês.', color: _pos));
        } else if (p > 0) {
          final eta = DateTime(now.year, now.month + (rest / p).ceil());
          lines.add(t('Ritmo atual de ${m(p)}/mês: conclui em ${fmt(eta)}. Faltam ${m(perMonth - p)}/mês para cumprir o prazo.', color: _warn));
        } else {
          lines.add(t('Nenhum depósito recente. Comece em Metas > Guardar.', color: _warn));
        }
        if (perMonth > capacity) {
          lines.add(t('Cabe no orçamento? Não: precisa de ${m(perMonth)}/mês e a sobra estimada é ${m(capacity)}/mês (faltam ${m(perMonth - capacity)}).', color: _warn));
          final c = cuts();
          if (c.isNotEmpty) {
            lines.add(t('Para fechar a conta:'));
            for (final s in c) {
              lines.add(t('• $s'));
            }
          }
          if (capacity > 0) {
            final mo = (rest / capacity).ceil();
            lines.add(t('• Ou estenda o prazo para ~$mo meses guardando ${m(capacity)}/mês.'));
          }
        } else {
          lines.add(t('Cabe no orçamento: a sobra estimada é ${m(capacity)}/mês.', color: _pos));
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(g.name, style: tt.titleMedium)),
            Chip(
              label: Text('Prioridade $rank'),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: g.pct, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 6),
          Text('${m(g.saved)} de ${m(g.target)} (${(g.pct * 100).toStringAsFixed(0)}%)'),
          ...lines,
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final mk in [25, 50, 75, 100])
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(g.pct * 100 >= mk ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16, color: g.pct * 100 >= mk ? _pos : null),
                label: Text('$mk%'),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final need = fixedTotal + baseVar;
    final hasEmerg = goals.any(isEmerg);
    final sorted = [...goals]..sort(cmp);

    return Scaffold(
      appBar: AppBar(title: const Text('Conselheiro financeiro')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Seu mês em números', style: tt.titleMedium),
                    const SizedBox(height: 8),
                    line('Renda do mês', m(renda)),
                    line('Contas fixas', m(fixedTotal)),
                    line('Meta de guardar', m(saveTarget)),
                    line('Gasto do dia a dia típico', m(baseVar)),
                    const Divider(),
                    line('Sobra estimada por mês', m(capacity), bold: true),
                    Text(
                      histMonths > 0
                          ? 'Baseado na média dos últimos $histMonths mês(es).'
                          : 'Baseado no que você gastou até agora; fica mais preciso com o tempo.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => PlanPage(month: DateTime(now.year, now.month))));
                        load();
                      },
                      child: const Text('Abrir planejamento'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text('Diagnóstico', style: tt.titleMedium),
              const SizedBox(height: 4),
              for (final d in diags)
                Card(
                  child: ListTile(
                    leading: Icon(
                      d.level == 0 ? Icons.check_circle : (d.level == 1 ? Icons.warning_amber_rounded : Icons.error),
                      color: d.level == 0 ? _pos : (d.level == 1 ? _warn : _neg),
                    ),
                    title: Text(d.title),
                    subtitle: Text(d.text),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Plano para suas metas', style: tt.titleMedium),
              const SizedBox(height: 4),
              if (!hasEmerg && need > 0)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Comece pela base: uma reserva de emergência.'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () async {
                          await DB.addGoal('Reserva de emergência', need * 3, null);
                          load();
                        },
                        child: Text('Criar reserva de 3 meses (${m(need * 3)})'),
                      ),
                    ]),
                  ),
                ),
              if (goals.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Você ainda não tem metas. Crie uma (viagem, notebook, reserva...) e eu monto o plano.'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          await Navigator.push(
                              context, MaterialPageRoute(builder: (_) => GoalsPage(sobra: capacity)));
                          load();
                        },
                        child: const Text('Criar meta'),
                      ),
                    ]),
                  ),
                ),
              for (var i = 0; i < sorted.length; i++) goalCard(sorted[i], i + 1),
              if (goals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.savings),
                    label: const Text('Guardar nas metas'),
                    onPressed: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => GoalsPage(sobra: capacity)));
                      load();
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Sugestões automáticas, baseadas nos seus números e em referências comuns de educação financeira (como a regra 50/30/20). Não substituem a orientação de um profissional.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
            ]),
    );
  }
}
