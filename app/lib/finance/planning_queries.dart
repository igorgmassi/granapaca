// Pure analytics, planning, NFC-e parsing, CSV/JSON export, statement import,
// and local read-only financial Q&A functions. Zero widgets and zero I/O.

import 'dart:convert';
import 'dart:math' as math;

import '../api/api_models.dart';
import '../demo/demo_data.dart';
import 'model.dart';
import 'queries.dart';
import 'taxonomy.dart';

/// Maximum safe integer cent value (`2^53 - 1`) supported identically across
/// native 64-bit Dart VM and Web/JS runtimes without silent overflow.
const int maxSafeCents = 9007199254740991;

/// Parses a BRL or decimal numeric string into exact integer cents
/// without floating-point drift or silent integer overflow (ADR-013).
/// Supports `"300"`, `"300,50"`, `"1.200,50"`, `"R$ 49,90"`, and `"49.90"`.
int? parseBrlToCents(String raw) {
  var cleaned = raw
      .trim()
      .replaceAll(RegExp(r'[Rr]\$'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return null;

  final negative = cleaned.startsWith('-') || cleaned.startsWith('−');
  if (negative) {
    cleaned = cleaned.substring(1);
  } else if (cleaned.startsWith('+')) {
    cleaned = cleaned.substring(1);
  }

  // Decide whether comma or dot is the decimal separator with strict
  // thousands-grouping validation so decimals like "0.125" or "1.2345" are
  // never multiplied by 1000x/10000x and malformed strings like "1.23.45" are
  // rejected.
  final lastComma = cleaned.lastIndexOf(',');
  final lastDot = cleaned.lastIndexOf('.');
  String intPart;
  String fracPart = '';

  if (lastComma != -1 && lastDot != -1) {
    if (lastComma > lastDot) {
      // pt-BR: 1.234,56
      if (cleaned.indexOf(',') != lastComma) return null;
      final rawInt = cleaned.substring(0, lastComma);
      if (!RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(rawInt)) return null;
      intPart = rawInt.replaceAll('.', '');
      fracPart = cleaned.substring(lastComma + 1);
    } else {
      // en-US: 1,234.56
      if (cleaned.indexOf('.') != lastDot) return null;
      final rawInt = cleaned.substring(0, lastDot);
      if (!RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(rawInt)) return null;
      intPart = rawInt.replaceAll(',', '');
      fracPart = cleaned.substring(lastDot + 1);
    }
  } else if (lastComma != -1) {
    if (cleaned.indexOf(',') != lastComma) {
      // Multiple commas only valid as strict en-US integer thousands grouping.
      if (!RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(cleaned)) return null;
      intPart = cleaned.replaceAll(',', '');
    } else {
      intPart = cleaned.substring(0, lastComma);
      fracPart = cleaned.substring(lastComma + 1);
    }
  } else if (lastDot != -1) {
    if (cleaned.indexOf('.') != lastDot) {
      // Multiple dots only valid as strict pt-BR integer thousands grouping.
      if (!RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(cleaned)) return null;
      intPart = cleaned.replaceAll('.', '');
    } else {
      final beforeDot = cleaned.substring(0, lastDot);
      final afterDot = cleaned.substring(lastDot + 1);
      if (afterDot.length == 3 &&
          RegExp(r'^[1-9]\d{0,2}$').hasMatch(beforeDot)) {
        // pt-BR thousands separator like "1.200" -> 1200 reais.
        // Leading-zero values like "0.125" do NOT match and fall through as
        // decimal fractions!
        intPart = '$beforeDot$afterDot';
      } else {
        // Decimal dot like "49.90", "49.9", "0.125", or "1.2345".
        intPart = beforeDot;
        fracPart = afterDot;
      }
    }
  } else {
    intPart = cleaned;
  }

  if (intPart.isEmpty) intPart = '0';
  if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
  if (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart)) return null;

  final bigReais = BigInt.tryParse(intPart);
  if (bigReais == null) return null;

  final paddedFrac = fracPart.padRight(2, '0');
  final centsDigits = paddedFrac.substring(0, 2);
  var cents = int.parse(centsDigits);
  if (paddedFrac.length > 2 && int.parse(paddedFrac[2]) >= 5) {
    cents += 1;
  }

  final bigTotal = bigReais * BigInt.from(100) + BigInt.from(cents);
  if (bigTotal > BigInt.from(maxSafeCents)) return null;

  final total = bigTotal.toInt();
  return negative ? -total : total;
}

/// Builds a full calendar-month spending heatmap (days 1..N) using 5 Caramelo
/// intensity buckets (`1..5`) plus `0` for days with zero net spending.
List<DailySpendingCell> dailySpendingHeatmap(
  Iterable<Transaction> transactions,
  DateTime month,
) {
  final year = month.year;
  final monthNumber = month.month;
  final daysInMonth = DateTime(year, monthNumber + 1, 0).day;
  final spentByDay = List<int>.filled(daysInMonth, 0);
  final countByDay = List<int>.filled(daysInMonth, 0);

  for (final t in transactions) {
    if (!isSpending(t)) continue;
    if (t.date.year != year || t.date.month != monthNumber) continue;
    final idx = t.date.day - 1;
    if (idx < 0 || idx >= daysInMonth) continue;
    spentByDay[idx] -= t.amountCents;
    countByDay[idx] += 1;
  }

  var maxDayCents = 0;
  for (var i = 0; i < daysInMonth; i++) {
    if (spentByDay[i] < 0) spentByDay[i] = 0;
    if (spentByDay[i] > maxDayCents) maxDayCents = spentByDay[i];
  }

  return List<DailySpendingCell>.generate(daysInMonth, (index) {
    final cents = spentByDay[index];
    final intensity = (cents <= 0 || maxDayCents <= 0)
        ? 0
        : ((cents / maxDayCents) * 5).ceil().clamp(1, 5);
    return DailySpendingCell(
      date: DateTime(year, monthNumber, index + 1),
      spentCents: cents,
      intensity: intensity,
      transactionCount: countByDay[index],
    );
  }, growable: false);
}

/// Computes the 50/30/20 rule breakdown for [month]:
/// - Needs = `Essentiality.essential`
/// - Wants = `Essentiality.important` + `Essentiality.flexible`
/// - Savings = `max(0, income - totalSpent)`
FiftyThirtyTwenty fiftyThirtyTwenty(
  Iterable<Transaction> transactions,
  DateTime month,
) {
  final (from, to) = monthRange(month);
  var incomeCents = 0;
  var needsCents = 0;
  var wantsCents = 0;
  var totalSpentCents = 0;

  for (final t in transactions) {
    if (t.date.isBefore(from) || !t.date.isBefore(to)) continue;
    if (isIncome(t)) {
      incomeCents += t.amountCents;
      continue;
    }
    if (!isSpending(t)) continue;
    totalSpentCents -= t.amountCents;

    if (t.splits.isNotEmpty) {
      final sign = t.amountCents < 0 ? 1 : -1;
      for (final split in t.splits) {
        final ess = split.essentiality ?? t.essentiality;
        final delta = sign * split.amountCents.abs();
        if (ess == Essentiality.essential) {
          needsCents += delta;
        } else {
          wantsCents += delta;
        }
      }
    } else {
      if (t.essentiality == Essentiality.essential) {
        needsCents -= t.amountCents;
      } else {
        wantsCents -= t.amountCents;
      }
    }
  }

  needsCents = math.max(0, needsCents);
  wantsCents = math.max(0, wantsCents);
  totalSpentCents = math.max(0, totalSpentCents);
  final savingsCents = math.max(0, incomeCents - totalSpentCents);

  return FiftyThirtyTwenty(
    incomeCents: incomeCents,
    needsCents: needsCents,
    wantsCents: wantsCents,
    savingsCents: savingsCents,
  );
}

/// Compares spending in [month] against the immediately preceding month,
/// returning overall delta and per-category deltas ordered by magnitude.
MonthComparison monthComparison(
  Iterable<Transaction> transactions,
  DateTime month,
) {
  final currentMonth = DateTime(month.year, month.month);
  final previousMonth = DateTime(month.year, month.month - 1);
  final (curFrom, curTo) = monthRange(currentMonth);
  final (prevFrom, prevTo) = monthRange(previousMonth);

  final currentTxs = <Transaction>[];
  final previousTxs = <Transaction>[];

  for (final t in transactions) {
    if (!isSpending(t)) continue;
    if (!t.date.isBefore(curFrom) && t.date.isBefore(curTo)) {
      currentTxs.add(t);
    } else if (!t.date.isBefore(prevFrom) && t.date.isBefore(prevTo)) {
      previousTxs.add(t);
    }
  }

  final currentRanking = categoryRanking(currentTxs);
  final previousRanking = categoryRanking(previousTxs);

  final curByCat = {for (final c in currentRanking) c.category: c.cents};
  final prevByCat = {for (final c in previousRanking) c.category: c.cents};

  final currentSpentCents = curByCat.values.fold(0, (a, b) => a + b);
  final previousSpentCents = prevByCat.values.fold(0, (a, b) => a + b);
  final deltaCents = currentSpentCents - previousSpentCents;
  final deltaPercent = previousSpentCents > 0
      ? deltaCents / previousSpentCents
      : (currentSpentCents > 0 ? 1.0 : 0.0);

  final allCats = <SpendingCategory?>{...curByCat.keys, ...prevByCat.keys};
  final deltas = <CategoryDelta>[
    for (final cat in allCats)
      (
        category: cat,
        currentCents: curByCat[cat] ?? 0,
        previousCents: prevByCat[cat] ?? 0,
        deltaCents: (curByCat[cat] ?? 0) - (prevByCat[cat] ?? 0),
      ),
  ]..sort((a, b) => b.deltaCents.abs().compareTo(a.deltaCents.abs()));

  return MonthComparison(
    currentMonth: currentMonth,
    previousMonth: previousMonth,
    currentSpentCents: currentSpentCents,
    previousSpentCents: previousSpentCents,
    deltaCents: deltaCents,
    deltaPercent: deltaPercent,
    categoryDeltas: List.unmodifiable(deltas),
  );
}

/// Projects end-of-month spending from the daily pace of regular expenses,
/// explicitly excluding transactions flagged as [Transaction.isAtypical] from
/// the extrapolated run-rate.
MonthProjection projectMonthEndSpending(
  Iterable<Transaction> transactions,
  DateTime month,
  DateTime today,
) {
  final targetMonth = DateTime(month.year, month.month);
  final (from, to) = monthRange(targetMonth);
  final totalDays = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;

  var regularSpentCents = 0;
  var atypicalSpentCents = 0;
  var atypicalCount = 0;

  for (final t in transactions) {
    if (!isSpending(t)) continue;
    if (t.date.isBefore(from) || !t.date.isBefore(to)) continue;
    if (t.isAtypical) {
      atypicalSpentCents -= t.amountCents;
      atypicalCount++;
    } else {
      regularSpentCents -= t.amountCents;
    }
  }

  regularSpentCents = math.max(0, regularSpentCents);
  atypicalSpentCents = math.max(0, atypicalSpentCents);

  final int elapsedDays;
  final todayMonth = DateTime(today.year, today.month);
  if (todayMonth.isAfter(targetMonth)) {
    elapsedDays = totalDays;
  } else if (todayMonth.isBefore(targetMonth)) {
    elapsedDays = 0;
  } else {
    elapsedDays = today.day.clamp(1, totalDays);
  }

  final int projectedRegularCents;
  if (elapsedDays <= 0) {
    projectedRegularCents = 0;
  } else if (elapsedDays >= totalDays) {
    projectedRegularCents = regularSpentCents;
  } else {
    projectedRegularCents = (regularSpentCents * totalDays / elapsedDays)
        .round();
  }

  return MonthProjection(
    month: targetMonth,
    elapsedDays: elapsedDays,
    totalDays: totalDays,
    regularSpentCents: regularSpentCents,
    atypicalSpentCents: atypicalSpentCents,
    projectedRegularCents: projectedRegularCents,
    projectedTotalCents: projectedRegularCents + atypicalSpentCents,
    atypicalCount: atypicalCount,
  );
}

/// Detects recurring merchants/subscriptions appearing across >= 2 distinct
/// months with a consistent monthly cadence (excluding installments and
/// atypical one-off expenses).
List<DetectedSubscription> detectSubscriptions(
  Iterable<Transaction> transactions,
) {
  final byMerchant = <String, List<Transaction>>{};
  for (final t in transactions) {
    if (t.kind != TxKind.expense) continue;
    if (t.isAtypical || t.installment != null) continue;
    final key = merchantKeyFor(t.description);
    if (key.isEmpty) continue;
    byMerchant.putIfAbsent(key, () => []).add(t);
  }

  final results = <DetectedSubscription>[];
  for (final entry in byMerchant.entries) {
    final txs = entry.value;
    final byMonthCount = <(int, int), int>{};
    for (final t in txs) {
      final mk = (t.date.year, t.date.month);
      byMonthCount[mk] = (byMonthCount[mk] ?? 0) + 1;
    }
    if (byMonthCount.length < 2) continue;

    // Skip frequent multi-visit merchants (e.g. supermarkets / bakeries).
    final maxPerMonth = byMonthCount.values.reduce(math.max);
    if (maxPerMonth > 1) continue;

    final amounts = [for (final t in txs) t.amountCents.abs()];
    final mean = amounts.fold(0, (a, b) => a + b) / amounts.length;
    if (mean <= 0) continue;

    final maxDeviation = amounts
        .map((a) => (a - mean).abs() / mean)
        .reduce(math.max);
    final days = [for (final t in txs) t.date.day]..sort();
    final daySpread = days.last - days.first;

    // Require relatively stable monthly timing and price.
    if (daySpread > 7 || maxDeviation > 0.35) continue;

    txs.sort((a, b) => b.date.compareTo(a.date));
    final latest = txs.first;
    final typicalDay = days[days.length ~/ 2];

    results.add(
      DetectedSubscription(
        merchantKey: entry.key,
        displayName: latest.description,
        averageCents: mean.round(),
        monthsCount: byMonthCount.length,
        typicalDayOfMonth: typicalDay,
        lastDate: latest.date,
        category: latest.category,
      ),
    );
  }

  int priority(DetectedSubscription s) {
    if (s.category == SpendingCategory.services) return 0;
    if (s.category == SpendingCategory.housing) return 1;
    if (s.category == SpendingCategory.health) return 2;
    return 3;
  }

  results.sort((a, b) {
    final p = priority(a).compareTo(priority(b));
    if (p != 0) return p;
    return b.averageCents.compareTo(a.averageCents);
  });

  return List.unmodifiable(results);
}

const Map<String, SpendingCategory> _categorySynonyms = {
  'moradia': SpendingCategory.housing,
  'aluguel': SpendingCategory.housing,
  'casa': SpendingCategory.housing,
  'alimentacao': SpendingCategory.food,
  'comida': SpendingCategory.food,
  'mercado': SpendingCategory.food,
  'supermercado': SpendingCategory.food,
  'transporte': SpendingCategory.transport,
  'combustivel': SpendingCategory.transport,
  'saude': SpendingCategory.health,
  'farmacia': SpendingCategory.health,
  'educacao': SpendingCategory.education,
  'lazer': SpendingCategory.leisure,
  'compras': SpendingCategory.shopping,
  'servicos': SpendingCategory.services,
  'assinaturas': SpendingCategory.services,
  'outros': SpendingCategory.other,
};

/// Parses a natural-language pt-BR spending alert rule such as:
/// `"me avise quando delivery passar de R$ 300"` or
/// `"avise quando alimentação passar de R$ 1.200,00"`.
SpendingAlertRule? parseSpendingAlertRule(String rawInput, {String? id}) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) return null;

  final normalized = normalizeText(trimmed);
  final amountMatch = RegExp(
    r'(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)',
  ).allMatches(normalized).lastOrNull;
  if (amountMatch == null) return null;

  final thresholdCents = parseBrlToCents(amountMatch.group(1)!);
  if (thresholdCents == null || thresholdCents <= 0) return null;

  // Try extracting the subject between "quando/se" and "passar/ultrapassar/chegar/exceder".
  String subject = '';
  final clauseMatch = RegExp(
    r'\b(?:quando|se)\s+(?:os?\s+gastos?\s+(?:com|em|de)\s+|gastos?\s+(?:com|em|de)\s+)?([a-z0-9\s/+-]+?)\s+(?:passar|passarem|ultrapassar|ultrapassarem|exceder|excederem|chegar|chegarem|bater|baterem)',
  ).firstMatch(normalized);
  if (clauseMatch != null) {
    subject = clauseMatch.group(1)!.trim();
  } else {
    // Fallback: strip boilerplate words and numbers.
    subject = normalized
        .replaceAll(
          RegExp(
            r'\b(me|avise|avisar|alerta|alertar|notifique|quando|se|passar|ultrapassar|exceder|de|do|da|dos|das|r\$|reais|gastos|gasto|mes|este)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[\d.,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  SpendingCategory? category;
  String? keyword;

  if (subject.isNotEmpty) {
    for (final entry in _categorySynonyms.entries) {
      if (subject == entry.key || subject.split(' ').contains(entry.key)) {
        category = entry.value;
        break;
      }
    }
    if (category == null) {
      keyword = subject;
    }
  }

  final targetLabel = category != null
      ? category.label
      : (keyword != null && keyword.isNotEmpty
            ? '${keyword[0].toUpperCase()}${keyword.substring(1)}'
            : 'Gastos totais');

  return SpendingAlertRule(
    id: id ?? 'alert-rule-${trimmed.hashCode.abs()}',
    rawExpression: trimmed,
    label: '$targetLabel > ${formatBrl(thresholdCents)}',
    thresholdCents: thresholdCents,
    category: category,
    keyword: keyword,
  );
}

/// Evaluates [rule] against [transactions] for [month].
({int currentCents, bool triggered, double ratio}) evaluateSpendingAlertRule(
  SpendingAlertRule rule,
  Iterable<Transaction> transactions,
  DateTime month,
) {
  final (from, to) = monthRange(month);
  final kw = rule.keyword == null ? null : normalizeText(rule.keyword!);
  var currentCents = 0;

  for (final t in transactions) {
    if (!isSpending(t)) continue;
    if (t.date.isBefore(from) || !t.date.isBefore(to)) continue;

    if (rule.category != null) {
      if (t.splits.isNotEmpty) {
        final sign = t.amountCents < 0 ? 1 : -1;
        for (final s in t.splits) {
          if ((s.category ?? t.category) == rule.category) {
            currentCents += sign * s.amountCents.abs();
          }
        }
      } else if (t.category == rule.category) {
        currentCents -= t.amountCents;
      }
    } else if (kw != null && kw.isNotEmpty) {
      final descMatches = normalizeText(t.description).contains(kw);
      final tagMatches = t.tags.any((tag) => normalizeText(tag).contains(kw));
      final splitMatches = t.splits.any(
        (s) => normalizeText(s.description).contains(kw),
      );
      if (descMatches || tagMatches || splitMatches) {
        currentCents -= t.amountCents;
      }
    } else {
      currentCents -= t.amountCents;
    }
  }

  currentCents = math.max(0, currentCents);
  final ratio = rule.thresholdCents <= 0
      ? 0.0
      : currentCents / rule.thresholdCents;
  return (
    currentCents: currentCents,
    triggered: rule.isActive && currentCents > rule.thresholdCents,
    ratio: ratio,
  );
}

String _unescapeXml(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .trim();

String? _xmlTag(String xml, String tagName) {
  final match = RegExp(
    '<$tagName(?:\\s[^>]*)?>([\\s\\S]*?)</$tagName>',
    caseSensitive: false,
  ).firstMatch(xml);
  return match == null ? null : _unescapeXml(match.group(1)!);
}

(SpendingCategory, Essentiality) _suggestReceiptItemClassification(
  String productName,
) {
  final norm = normalizeText(productName);
  if (RegExp(
    r'dipirona|remedio|farmacia|vitamina|analgesico|comprimido|curativo',
  ).hasMatch(norm)) {
    return (SpendingCategory.health, Essentiality.essential);
  }
  if (RegExp(
    r'detergente|sabao|amaciante|limpeza|papel higienico|desinfetante',
  ).hasMatch(norm)) {
    return (SpendingCategory.housing, Essentiality.essential);
  }
  if (RegExp(
    r'cerveja|vinho|refrigerante|chocolate|sorvete|doce|salgadinho|biscoito',
  ).hasMatch(norm)) {
    return (SpendingCategory.food, Essentiality.flexible);
  }
  if (RegExp(
    r'arroz|feijao|leite|pao|cafe|acucar|fruta|verdura|legume|ovo|carne|frango|oleo|macarrao',
  ).hasMatch(norm)) {
    return (SpendingCategory.food, Essentiality.essential);
  }
  if (RegExp(r'gasolina|etanol|diesel|combustivel').hasMatch(norm)) {
    return (SpendingCategory.transport, Essentiality.important);
  }
  return (SpendingCategory.shopping, Essentiality.important);
}

const Map<String, String> _ufCodeNames = {
  '12': 'AC',
  '27': 'AL',
  '13': 'AM',
  '16': 'AP',
  '29': 'BA',
  '23': 'CE',
  '53': 'DF',
  '32': 'ES',
  '52': 'GO',
  '21': 'MA',
  '31': 'MG',
  '50': 'MS',
  '51': 'MT',
  '15': 'PA',
  '25': 'PB',
  '26': 'PE',
  '22': 'PI',
  '41': 'PR',
  '33': 'RJ',
  '24': 'RN',
  '11': 'RO',
  '14': 'RR',
  '43': 'RS',
  '42': 'SC',
  '28': 'SE',
  '35': 'SP',
  '17': 'TO',
};

/// Parses a Brazilian NFC-e XML payload OR a SEFAZ NFC-e QR Code URL (such as
/// `sefaz.es.gov.br` or any standard `?p=<44-digit-key>|...` URL).
ReceiptParseResult parseNfceInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException(
      'Cole o XML da NFC-e ou a URL do QR Code para analisar.',
    );
  }

  // Path 1: NFC-e XML
  if (trimmed.startsWith('<') &&
      (trimmed.contains('<prod') ||
          trimmed.contains('<NFe') ||
          trimmed.contains('<infNFe'))) {
    final emitBlock = _xmlTag(trimmed, 'emit');
    final issuerName =
        (emitBlock != null ? _xmlTag(emitBlock, 'xNome') : null) ??
        _xmlTag(trimmed, 'xNome') ??
        'Estabelecimento (NFC-e)';

    final keyMatch = RegExp(r'(?:Id="NFe|<chNFe>)(\d{44})').firstMatch(trimmed);
    final accessKey = keyMatch?.group(1);

    final rawDate = _xmlTag(trimmed, 'dhEmi') ?? _xmlTag(trimmed, 'dEmi');
    final issuedAt = rawDate == null ? null : DateTime.tryParse(rawDate);

    final detMatches = RegExp(
      r'<det\b[^>]*>([\s\S]*?)</det>',
      caseSensitive: false,
    ).allMatches(trimmed);

    final items = <ReceiptItem>[];
    var itemsSumCents = 0;

    for (final m in detMatches) {
      final detXml = m.group(1) ?? '';
      final prodXml = _xmlTag(detXml, 'prod') ?? detXml;
      final name = _xmlTag(prodXml, 'xProd');
      final rawVProd = _xmlTag(prodXml, 'vProd');
      if (name == null || name.isEmpty || rawVProd == null) continue;
      final grossCents = parseBrlToCents(rawVProd) ?? 0;
      final discountCents =
          parseBrlToCents(_xmlTag(prodXml, 'vDesc') ?? '') ?? 0;
      final netCents = math.max(0, grossCents - discountCents);
      if (netCents <= 0) continue;

      final rawQty = _xmlTag(prodXml, 'qCom')?.replaceAll(',', '.');
      final qty = double.tryParse(rawQty ?? '') ?? 1.0;
      final (suggestedCat, suggestedEss) = _suggestReceiptItemClassification(
        name,
      );

      itemsSumCents += netCents;
      items.add(
        ReceiptItem(
          description: name,
          amountCents: netCents,
          quantity: qty,
          suggestedCategory: suggestedCat,
          suggestedEssentiality: suggestedEss,
        ),
      );
    }

    final rawVNf = _xmlTag(trimmed, 'vNF');
    final totalCents =
        (rawVNf != null ? parseBrlToCents(rawVNf) : null) ?? itemsSumCents;

    if (items.isEmpty && totalCents <= 0) {
      throw const FormatException(
        'XML recebido, mas nenhum item (<det><prod>) ou valor (<vNF>) foi encontrado.',
      );
    }

    return ReceiptParseResult(
      sourceType: 'nfce_xml',
      issuerName: issuerName,
      totalCents: totalCents,
      items: List.unmodifiable(items),
      accessKey: accessKey,
      issuedAt: issuedAt,
    );
  }

  // Path 2: SEFAZ NFC-e QR URL or 44-digit access key
  final uri = Uri.tryParse(trimmed);
  final keyCandidate = _extractNfceAccessKey(trimmed, uri);
  if (keyCandidate == null) {
    throw const FormatException(
      'Formato não reconhecido. Cole o XML completo da NFC-e ou a URL do QR '
      'Code da SEFAZ (com chave de acesso de 44 dígitos).',
    );
  }

  final ufCode = keyCandidate.substring(0, 2);
  final uf = _ufCodeNames[ufCode] ?? 'BR';
  final yy = int.tryParse(keyCandidate.substring(2, 4));
  final mm = int.tryParse(keyCandidate.substring(4, 6));
  DateTime? issuedAt;
  if (yy != null && mm != null && mm >= 1 && mm <= 12) {
    issuedAt = DateTime(2000 + yy, mm, 1);
  }

  // Extract optional total value from QR v1 query string (`vNF=...` or pipe field).
  int totalCents = 0;
  if (uri != null) {
    final vnfParam = uri.queryParameters['vNF'] ?? uri.queryParameters['vnf'];
    if (vnfParam != null) {
      totalCents = parseBrlToCents(vnfParam) ?? 0;
    } else {
      final pParam = uri.queryParameters['p'];
      if (pParam != null) {
        final parts = pParam.split('|');
        // In NFC-e QR v1, field index 4 is often vNF (decimal with dot).
        if (parts.length > 4 && RegExp(r'^\d+\.\d{2}$').hasMatch(parts[4])) {
          totalCents = parseBrlToCents(parts[4]) ?? 0;
        }
      }
    }
  }

  final host = uri?.host.isNotEmpty == true ? uri!.host : 'SEFAZ-$uf';
  final issuerName = 'NFC-e $uf ($host)';
  final items = <ReceiptItem>[
    if (totalCents > 0)
      ReceiptItem(
        description: 'Itens da NFC-e $uf (chave ...${keyCandidate.substring(36)})',
        amountCents: totalCents,
        suggestedCategory: SpendingCategory.food,
        suggestedEssentiality: Essentiality.essential,
      ),
  ];

  return ReceiptParseResult(
    sourceType: 'nfce_qr_url',
    issuerName: issuerName,
    totalCents: totalCents,
    items: List.unmodifiable(items),
    accessKey: keyCandidate,
    issuedAt: issuedAt,
    sourceUrl: uri != null && uri.hasScheme ? trimmed : null,
  );
}

String? _extractNfceAccessKey(String raw, Uri? uri) {
  if (uri != null) {
    final pParam = uri.queryParameters['p'];
    if (pParam != null) {
      final first = pParam.split('|').first.trim();
      if (RegExp(r'^\d{44}$').hasMatch(first)) return first;
    }
    final chParam =
        uri.queryParameters['chNFe'] ?? uri.queryParameters['chnfe'];
    if (chParam != null && RegExp(r'^\d{44}$').hasMatch(chParam.trim())) {
      return chParam.trim();
    }
  }
  final match = RegExp(r'(?<!\d)(\d{44})(?!\d)').firstMatch(raw);
  return match?.group(1);
}

/// Converts [items] into exact-cent [TxSplit] entries reconciling against
/// [targetTotalCents.abs()] so `validateSplitTotal` always holds (RN-24).
List<TxSplit> receiptItemsToSplits(
  List<ReceiptItem> items,
  int targetTotalCents,
) {
  final target = targetTotalCents.abs();
  if (target <= 0) return const [];
  if (items.isEmpty) {
    return [
      TxSplit(
        id: 'split-nfce-1',
        description: 'Itens da nota fiscal',
        amountCents: target,
        category: SpendingCategory.food,
        essentiality: Essentiality.essential,
      ),
    ];
  }

  final result = <TxSplit>[];
  var sum = 0;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.amountCents <= 0) continue;
    sum += item.amountCents;
    result.add(
      TxSplit(
        id: 'split-nfce-${i + 1}',
        description: item.description,
        amountCents: item.amountCents,
        category: item.suggestedCategory,
        essentiality: item.suggestedEssentiality,
      ),
    );
  }

  if (result.isEmpty) return const [];
  if (sum == target) return List.unmodifiable(result);

  if (sum < target) {
    // Add explicit difference line (e.g. freight/tax/service fee).
    result.add(
      TxSplit(
        id: 'split-nfce-diff',
        description: 'Acréscimos / diferença da nota',
        amountCents: target - sum,
        category: result.first.category,
        essentiality: result.first.essentiality,
      ),
    );
    return List.unmodifiable(result);
  }

  // If items sum exceeds target (e.g. receipt-level discount), distribute
  // proportionally using BigInt exact arithmetic so the split sum ALWAYS
  // equals target in exact cents (RN-24) and no part becomes zero/negative.
  if (target <= 0) return const [];

  // When there are more items than total cents (e.g. 5 items under a discount
  // leaving R$ 0,03), consolidate to the top `target` largest items at 1 cent
  // each so every part stays positive and sums to exact `target`.
  if (result.length > target) {
    final sorted = [...result]
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return List.unmodifiable([
      for (var i = 0; i < target; i++) sorted[i].copyWith(amountCents: 1),
    ]);
  }

  final bigTarget = BigInt.from(target);
  final bigSum = BigInt.from(sum);
  final scaled = <TxSplit>[];
  var allocated = 0;
  for (var i = 0; i < result.length; i++) {
    final part = result[i];
    final exactFloor = ((BigInt.from(part.amountCents) * bigTarget) ~/ bigSum)
        .toInt();
    final proportional = math.max(1, exactFloor);
    allocated += proportional;
    scaled.add(part.copyWith(amountCents: proportional));
  }

  var diff = target - allocated;
  if (diff > 0) {
    var largestIdx = 0;
    for (var i = 1; i < scaled.length; i++) {
      if (scaled[i].amountCents > scaled[largestIdx].amountCents) {
        largestIdx = i;
      }
    }
    scaled[largestIdx] = scaled[largestIdx].copyWith(
      amountCents: scaled[largestIdx].amountCents + diff,
    );
  } else if (diff < 0) {
    // Reduce largest parts down to at most 1 cent each until exact sum matches.
    // Because scaled.length <= target, sum(amountCents - 1) >= -diff always.
    var excess = -diff;
    final order = List<int>.generate(scaled.length, (i) => i)
      ..sort((a, b) => scaled[b].amountCents.compareTo(scaled[a].amountCents));
    for (final idx in order) {
      if (excess <= 0) break;
      final available = scaled[idx].amountCents - 1;
      if (available <= 0) continue;
      final take = math.min(available, excess);
      scaled[idx] = scaled[idx].copyWith(
        amountCents: scaled[idx].amountCents - take,
      );
      excess -= take;
    }
  }
  return List.unmodifiable(scaled);
}

String _csvQuote(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Neutralizes spreadsheet formula injection (`=`, `+`, `-`, `@`, `\t`, `\r`)
/// on text columns (including after leading whitespace) before RFC 4180 quoting.
String _csvEscapeText(String value) {
  final trimmedLeft = value.trimLeft();
  final dangerous =
      value.startsWith('\t') ||
      value.startsWith('\r') ||
      (trimmedLeft.isNotEmpty &&
          const {'=', '+', '-', '@'}.contains(trimmedLeft[0]));
  return _csvQuote(dangerous ? "'$value" : value);
}

/// Builds an RFC 4180 compliant pt-BR CSV export of [transactions] with
/// formula-injection neutralization on text columns while keeping numeric
/// values intact.
String buildTransactionsCsv(
  Iterable<EffectiveTransaction> transactions,
  Dataset dataset,
) {
  final buffer = StringBuffer();
  buffer.write(
    'Data,Descrição,Descrição original,Banco,Conta,Tipo,Meio de pagamento,'
    'Categoria,Essencialidade,Atípica,Tags,Valor (R\$)\r\n',
  );
  for (final tx in transactions) {
    final acct = dataset.account(tx.accountId);
    final bank = dataset.bank(acct.bankId);
    final abs = tx.amountCents.abs();
    final decimalValue =
        '${tx.amountCents < 0 ? '-' : ''}${abs ~/ 100},'
        '${(abs % 100).toString().padLeft(2, '0')}';

    final textCells = [
      formatFullDate(tx.date),
      tx.description,
      tx.original.description,
      bank.name,
      acct.name,
      tx.kind.label,
      tx.paymentMethod.label,
      spendingCategoryLabel(tx.category),
      tx.essentiality?.label ?? '',
      tx.isAtypical ? 'Sim' : 'Não',
      tx.tags.join('; '),
    ].map(_csvEscapeText);
    final row = [...textCells, _csvQuote(decimalValue)].join(',');
    buffer.write('$row\r\n');
  }
  return buffer.toString();
}

/// Parsed contents of a GranaPaCá JSON backup file.
class BackupPayload {
  const BackupPayload({
    required this.banks,
    required this.accounts,
    required this.transactions,
    required this.rules,
    required this.adjustments,
    required this.budgets,
    required this.goals,
    required this.alertRules,
    this.receiptConsentAccepted = false,
    this.exportedAt,
  });

  final List<Bank> banks;
  final List<Account> accounts;
  final List<Transaction> transactions;
  final List<UserRule> rules;
  final List<TxAdjustment> adjustments;
  final List<Budget> budgets;
  final List<Goal> goals;
  final List<SpendingAlertRule> alertRules;
  final bool receiptConsentAccepted;
  final DateTime? exportedAt;
}

/// Builds a complete JSON backup payload covering banks, accounts,
/// transactions, rules, adjustments, budgets, goals, alert rules, and receipt
/// consent.
String buildBackupJson({
  required Dataset dataset,
  required List<UserRule> rules,
  required List<TxAdjustment> adjustments,
  required List<Budget> budgets,
  required List<Goal> goals,
  required List<SpendingAlertRule> alertRules,
  required String modeLabel,
  bool receiptConsentAccepted = false,
  DateTime? exportedAt,
}) {
  final payload = {
    'version': 1,
    'app': 'GranaPaCa',
    'mode': modeLabel,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'receiptConsentAccepted': receiptConsentAccepted,
    'banks': [for (final b in dataset.banks) bankToJson(b)],
    'accounts': [for (final a in dataset.accounts) accountToJson(a)],
    'transactions': [
      for (final t in dataset.transactions)
        {
          ...transactionToJson(t),
          'paymentMethod': t.paymentMethod?.name,
          'tags': t.tags,
          'isAtypical': t.isAtypical,
          'isCashEntry': t.isCashEntry,
          'splits': [for (final s in t.splits) txSplitToJson(s)],
        },
    ],
    'rules': [for (final r in rules) userRuleToJson(r)],
    'adjustments': [for (final a in adjustments) adjustmentToJson(a)],
    'budgets': [for (final b in budgets) budgetToJson(b)],
    'goals': [for (final g in goals) goalToJson(g)],
    'alertRules': [for (final a in alertRules) spendingAlertRuleToJson(a)],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

List<Map<String, dynamic>> _requireBackupObjectList(
  Map<String, dynamic> root,
  String key,
) {
  if (!root.containsKey(key) || root[key] == null) return const [];
  final raw = root[key];
  if (raw is! List) {
    throw FormatException('Campo "$key" inválido no backup JSON.');
  }
  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map<String, dynamic>) {
      throw FormatException(
        'Item inválido encontrado na lista "$key" do backup JSON.',
      );
    }
    out.add(item);
  }
  return out;
}

/// Parses and validates a JSON backup produced by [buildBackupJson].
/// Enforces strict JSON types, supported version, and RN-24 split invariants,
/// always throwing [FormatException] with a friendly pt-BR error if invalid.
BackupPayload parseBackupJson(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException(
      'Cole o conteúdo do backup JSON para restaurar seus dados.',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    throw const FormatException(
      'O texto informado não é um JSON válido. Confira se copiou o backup completo.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'Formato de backup inválido. Esperava um objeto JSON do GranaPaCá.',
    );
  }
  final rawVersion = decoded['version'];
  if (rawVersion != null && rawVersion != 1) {
    throw const FormatException(
      'Versão do backup JSON não suportada por esta versão do GranaPaCá.',
    );
  }
  final appName = decoded['app'];
  final hasCoreKeys =
      decoded.containsKey('banks') ||
      decoded.containsKey('accounts') ||
      decoded.containsKey('transactions');
  if ((appName != null && appName != 'GranaPaCa') || !hasCoreKeys) {
    throw const FormatException(
      'Este arquivo não parece ser um backup gerado pelo GranaPaCá.',
    );
  }
  final rawConsent = decoded['receiptConsentAccepted'];
  if (rawConsent != null && rawConsent is! bool) {
    throw const FormatException(
      'Campo "receiptConsentAccepted" inválido no backup JSON.',
    );
  }
  DateTime? exportedAt;
  final rawExportedAt = decoded['exportedAt'];
  if (rawExportedAt != null) {
    if (rawExportedAt is! String) {
      throw const FormatException(
        'Campo "exportedAt" inválido no backup JSON.',
      );
    }
    exportedAt = DateTime.tryParse(rawExportedAt);
    if (exportedAt == null) {
      throw const FormatException(
        'Data "exportedAt" inválida no backup JSON.',
      );
    }
  }

  final rawBanks = _requireBackupObjectList(decoded, 'banks');
  final rawAccounts = _requireBackupObjectList(decoded, 'accounts');
  final rawTransactions = _requireBackupObjectList(decoded, 'transactions');
  final rawRules = _requireBackupObjectList(decoded, 'rules');
  final rawAdjustments = _requireBackupObjectList(decoded, 'adjustments');
  final rawBudgets = _requireBackupObjectList(decoded, 'budgets');
  final rawGoals = _requireBackupObjectList(decoded, 'goals');
  final rawAlertRules = _requireBackupObjectList(decoded, 'alertRules');

  try {
    final banks = rawBanks.map(bankFromJson).toList(growable: false);
    final accounts = rawAccounts.map(accountFromJson).toList(growable: false);
    final transactions = rawTransactions
        .map(transactionFromJson)
        .toList(growable: false);
    for (final tx in transactions) {
      if (tx.splits.isNotEmpty && !validateSplitTotal(tx.amountCents, tx.splits)) {
        throw FormatException(
          'Divisão (splits) inválida no backup para "${tx.description}": a '
          'soma das partes não fecha o valor exato da transação.',
        );
      }
    }
    final rules = rawRules.map(userRuleFromJson).toList(growable: false);
    final adjustments = rawAdjustments
        .map(adjustmentFromJson)
        .toList(growable: false);
    final budgets = rawBudgets.map(budgetFromJson).toList(growable: false);
    final goals = rawGoals.map(goalFromJson).toList(growable: false);
    final alertRules = rawAlertRules
        .map(spendingAlertRuleFromJson)
        .toList(growable: false);

    return BackupPayload(
      banks: banks,
      accounts: accounts,
      transactions: transactions,
      rules: rules,
      adjustments: adjustments,
      budgets: budgets,
      goals: goals,
      alertRules: alertRules,
      receiptConsentAccepted: (rawConsent as bool?) ?? false,
      exportedAt: exportedAt,
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'Algum registro do backup JSON possui campos com formato incompatível.',
    );
  }
}

/// Parses OFX (`<STMTTRN>`) or simple CSV (`data,descricao,valor`) bank
/// statement text into preview [Transaction] records.
List<Transaction> parseStatementImport(
  String raw, {
  required String accountId,
  int startingId = 200000,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  var nextId = startingId;
  final result = <Transaction>[];

  // Path 1: OFX
  if (trimmed.toUpperCase().contains('<STMTTRN>')) {
    final blocks = RegExp(
      r'<STMTTRN>([\s\S]*?)(?:</STMTTRN>|(?=<STMTTRN>)|$)',
      caseSensitive: false,
    ).allMatches(trimmed);

    for (final b in blocks) {
      final body = b.group(1) ?? '';
      final amtMatch = RegExp(
        r'<TRNAMT>([^\r\n<]+)',
        caseSensitive: false,
      ).firstMatch(body);
      final dateMatch = RegExp(
        r'<DTPOSTED>(\d{8})',
        caseSensitive: false,
      ).firstMatch(body);
      final memoMatch =
          RegExp(r'<MEMO>([^\r\n<]+)', caseSensitive: false).firstMatch(body) ??
          RegExp(r'<NAME>([^\r\n<]+)', caseSensitive: false).firstMatch(body);

      if (amtMatch == null) continue;
      final cents = parseBrlToCents(amtMatch.group(1)!.trim());
      if (cents == null || cents == 0) continue;

      DateTime date = DateTime.now();
      if (dateMatch != null) {
        final d = dateMatch.group(1)!;
        final y = int.parse(d.substring(0, 4));
        final m = int.parse(d.substring(4, 6));
        final day = int.parse(d.substring(6, 8));
        final parsed = _strictCalendarDate(y, m, day);
        if (parsed == null) continue;
        date = parsed;
      }
      final description = memoMatch?.group(1)?.trim() ?? 'Lançamento OFX';
      result.add(
        Transaction(
          id: nextId++,
          accountId: accountId,
          date: date,
          description: description,
          amountCents: cents,
          kind: cents < 0 ? TxKind.expense : TxKind.income,
          paymentMethod: PaymentMethod.other,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  // Path 2: CSV (date,description,amount or semicolon-separated)
  final lines = trimmed
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final sep = line.contains(';') ? ';' : ',';
    final cols = _splitCsvLine(line, sep);
    if (cols.length < 3) continue;

    // Skip header row if first column isn't a date.
    final parsedDate = _parseFlexibleDate(cols[0].trim());
    if (parsedDate == null) continue;

    final description = cols[1].trim();
    final cents = parseBrlToCents(cols[2].trim());
    if (description.isEmpty || cents == null || cents == 0) continue;

    result.add(
      Transaction(
        id: nextId++,
        accountId: accountId,
        date: parsedDate,
        description: description,
        amountCents: cents,
        kind: cents < 0 ? TxKind.expense : TxKind.income,
        paymentMethod: PaymentMethod.other,
      ),
    );
  }
  return List.unmodifiable(result);
}

List<String> _splitCsvLine(String line, String sep) {
  final out = <String>[];
  final current = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        current.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == sep && !inQuotes) {
      out.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  out.add(current.toString());
  return out;
}

DateTime? _strictCalendarDate(int year, int month, int day) {
  if (year < 1900 ||
      year > 2100 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  final dt = DateTime(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) {
    return null;
  }
  return dt;
}

DateTime? _parseFlexibleDate(String raw) {
  final cleaned = raw.replaceAll('"', '').trim();
  final isoMatch = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[T\s].*)?$',
  ).firstMatch(cleaned);
  if (isoMatch != null) {
    return _strictCalendarDate(
      int.parse(isoMatch.group(1)!),
      int.parse(isoMatch.group(2)!),
      int.parse(isoMatch.group(3)!),
    );
  }
  final brMatch = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(cleaned);
  if (brMatch != null) {
    return _strictCalendarDate(
      int.parse(brMatch.group(3)!),
      int.parse(brMatch.group(2)!),
      int.parse(brMatch.group(1)!),
    );
  }
  return null;
}

const Map<String, int> _portugueseFullMonths = {
  'janeiro': 1,
  'fevereiro': 2,
  'marco': 3,
  'abril': 4,
  'maio': 5,
  'junho': 6,
  'julho': 7,
  'agosto': 8,
  'setembro': 9,
  'outubro': 10,
  'novembro': 11,
  'dezembro': 12,
};

const Map<String, int> _portugueseShortMonths = {
  'jan': 1,
  'fev': 2,
  'mar': 3,
  'abr': 4,
  'mai': 5,
  'jun': 6,
  'jul': 7,
  'ago': 8,
  'set': 9,
  'out': 10,
  'nov': 11,
  'dez': 12,
};

const Map<String, SpendingCategory> _explicitQaCategories = {
  'alimentacao': SpendingCategory.food,
  'comida': SpendingCategory.food,
  'moradia': SpendingCategory.housing,
  'transporte': SpendingCategory.transport,
  'saude': SpendingCategory.health,
  'educacao': SpendingCategory.education,
  'lazer': SpendingCategory.leisure,
  'compras': SpendingCategory.shopping,
  'servicos': SpendingCategory.services,
  'outros': SpendingCategory.other,
};

const Map<String, List<String>> _merchantAliasGroups = {
  'supermercado': ['supermercado', 'mercado', 'atacadao', 'hortifruti'],
  'mercado': ['supermercado', 'mercado', 'atacadao', 'hortifruti'],
  'padaria': ['padaria', 'panificadora', 'confeitaria'],
  'farmacia': ['farmacia', 'drogaria'],
  'drogaria': ['farmacia', 'drogaria'],
  'posto': ['posto', 'combustivel', 'gasolina', 'etanol'],
  'combustivel': ['posto', 'combustivel', 'gasolina', 'etanol'],
  'gasolina': ['posto', 'combustivel', 'gasolina', 'etanol'],
  'restaurante': ['restaurante', 'lanchonete', 'almoco', 'jantar'],
  'uber': ['uber', '99', 'corrida', 'aplicativo'],
  'corrida': ['uber', '99', 'corrida', 'aplicativo'],
  'streaming': ['streaming', 'cine', 'netflix', 'spotify', 'prime', 'disney'],
  'academia': ['academia', 'pilates', 'crossfit'],
  'internet': ['internet', 'fibra'],
  'aluguel': ['aluguel', 'condominio'],
  'livraria': ['livraria', 'livro'],
};

({DateTime month, String? matchedWord}) _resolveMonthFromQuestion(
  String normQ,
  DateTime fallbackMonth,
  Dataset data,
) {
  int? matchedMonthNum;
  String? matchedWord;

  for (final entry in _portugueseFullMonths.entries) {
    if (RegExp('\\b${entry.key}\\b').hasMatch(normQ)) {
      matchedMonthNum = entry.value;
      matchedWord = entry.key;
      break;
    }
  }

  if (matchedMonthNum == null) {
    for (final entry in _portugueseShortMonths.entries) {
      if (RegExp(
        '(?:\\b(?:em|de)\\s+${entry.key}\\b|\\b${entry.key}[/\\s]+20\\d{2}\\b)',
      ).hasMatch(normQ)) {
        matchedMonthNum = entry.value;
        matchedWord = entry.key;
        break;
      }
    }
  }

  if (matchedMonthNum == null) {
    return (
      month: DateTime(fallbackMonth.year, fallbackMonth.month),
      matchedWord: null,
    );
  }

  final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(normQ);
  int year;
  if (yearMatch != null) {
    year = int.parse(yearMatch.group(1)!);
  } else {
    final hasInFallbackYear = data.transactions.any(
      (t) => t.date.year == fallbackMonth.year && t.date.month == matchedMonthNum,
    );
    if (hasInFallbackYear) {
      year = fallbackMonth.year;
    } else {
      final matchingYears = data.transactions
          .where((t) => t.date.month == matchedMonthNum)
          .map((t) => t.date.year)
          .toList()
        ..sort();
      year = matchingYears.isNotEmpty ? matchingYears.last : fallbackMonth.year;
    }
  }

  return (month: DateTime(year, matchedMonthNum), matchedWord: matchedWord);
}

SpendingCategory? _matchExplicitQaCategory(String normQ) {
  for (final entry in _explicitQaCategories.entries) {
    if (RegExp('\\b${entry.key}\\b').hasMatch(normQ)) {
      return entry.value;
    }
  }
  return null;
}

/// Deterministic zero-cost, 100% offline read-only financial Q&A engine for
/// Paçoca (local-device mode, demo mode & offline server fallback). Always
/// cites the exact period and exact pt-BR figures computed directly from
/// [data].
AssistantMessage answerFinancialQuestion(
  String question,
  Dataset data,
  DateTime month, {
  List<Budget> budgets = const [],
  List<Goal> goals = const [],
  DateTime? today,
  String? replyId,
}) {
  final normQ = normalizeText(question);
  final resolvedMonth = _resolveMonthFromQuestion(normQ, month, data);
  final targetMonth = resolvedMonth.month;
  final periodLabel = formatMonthYear(targetMonth);
  final (from, to) = monthRange(targetMonth);
  final s = summary(data, targetMonth);
  final monthTxs = data.transactions
      .where((t) => !t.date.isBefore(from) && t.date.isBefore(to))
      .toList(growable: false);
  final ranking = categoryRanking(monthTxs);
  final now = today ?? data.today;
  final explicitCategory = _matchExplicitQaCategory(normQ);

  final asksTopIndividualExpenses =
      normQ.contains('maiores gastos') ||
      normQ.contains('maiores despesas') ||
      normQ.contains('maior gasto') ||
      normQ.contains('maior despesa') ||
      normQ.contains('top gastos') ||
      normQ.contains('top despesas') ||
      normQ.contains('gasto mais alto') ||
      normQ.contains('gastos mais altos') ||
      (normQ.contains('onde gastei mais') && !normQ.contains('categoria'));

  final asksComparison =
      normQ.contains('compar') ||
      normQ.contains('anterior') ||
      normQ.contains('diferenca') ||
      (normQ.contains('passado') && resolvedMonth.matchedWord == null);

  String text;
  List<String> figures;

  // 1. 50/30/20 question
  if (normQ.contains('50/30/20') ||
      normQ.contains('50 30 20') ||
      normQ.contains('essencialidade') ||
      normQ.contains('necessidade')) {
    final split = fiftyThirtyTwenty(data.transactions, targetMonth);
    text =
        'Em $periodLabel, sua divisão 50/30/20 ficou em '
        '${formatPercent(split.needsShare)} para Necessidades (Essencial: '
        '${formatBrl(split.needsCents)}), ${formatPercent(split.wantsShare)} '
        'para Desejos (Importante + Flexível: ${formatBrl(split.wantsCents)}) '
        'e ${formatPercent(split.savingsShare)} para Poupança '
        '(${formatBrl(split.savingsCents)}) sobre receitas de '
        '${formatBrl(split.incomeCents)}.';
    figures = [
      'Necessidades: ${formatPercent(split.needsShare)} (${formatBrl(split.needsCents)})',
      'Desejos: ${formatPercent(split.wantsShare)} (${formatBrl(split.wantsCents)})',
      'Poupança: ${formatPercent(split.savingsShare)} (${formatBrl(split.savingsCents)})',
    ];
  }
  // 2. Subscriptions / recurring question
  else if (normQ.contains('assinatura') ||
      normQ.contains('recorrente') ||
      normQ.contains('mensalidade')) {
    final subs = detectSubscriptions(data.transactions);
    final servicesShare = ranking
        .where((c) => c.category == SpendingCategory.services)
        .firstOrNull;
    if (subs.isEmpty) {
      if (servicesShare != null && servicesShare.cents > 0) {
        text =
            'Em $periodLabel, seus gastos na categoria Serviços e assinaturas '
            'somaram ${formatBrl(servicesShare.cents)} '
            '(${formatPercent(servicesShare.share)} dos gastos). Ainda preciso '
            'de pelo menos 2 meses para detectar cobranças recorrentes '
            'automaticamente.';
        figures = [
          'Serviços e assinaturas: ${formatBrl(servicesShare.cents)}',
          'Participação: ${formatPercent(servicesShare.share)}',
        ];
      } else {
        text =
            'Ainda não encontrei cobranças recorrentes em pelo menos 2 meses '
            'até $periodLabel.';
        figures = ['0 assinaturas detectadas'];
      }
    } else {
      final totalMonthly = subs.fold(0, (acc, x) => acc + x.averageCents);
      final topNames = subs
          .take(4)
          .map((x) => '${x.displayName} (${formatBrl(x.averageCents)})')
          .join(', ');
      final servicesNote = servicesShare != null
          ? ' Em $periodLabel, a categoria Serviços e assinaturas somou '
                '${formatBrl(servicesShare.cents)}.'
          : '';
      text =
          'Detectei ${subs.length} gasto(s) recorrente(s) com base nos meses '
          'disponíveis até $periodLabel, somando cerca de '
          '${formatBrl(totalMonthly)}/mês. Destaques: $topNames.$servicesNote';
      figures = [
        '${subs.length} recorrências',
        'Média mensal: ${formatBrl(totalMonthly)}',
        if (servicesShare != null)
          'Serviços ($periodLabel): ${formatBrl(servicesShare.cents)}',
      ];
    }
  }
  // 3. Projection question (excludes atypical expenses from daily run-rate)
  else if (normQ.contains('projecao') ||
      normQ.contains('previsao') ||
      normQ.contains('fim do mes')) {
    final proj = projectMonthEndSpending(data.transactions, targetMonth, now);
    final atypicalNote = proj.atypicalCount > 0
        ? ' (${proj.atypicalCount} despesa(s) atípica(s) de '
              '${formatBrl(proj.atypicalSpentCents)} fora do ritmo diário)'
        : '';
    text =
        'Para $periodLabel (dia ${proj.elapsedDays} de ${proj.totalDays}), '
        'seu gasto regular acumulado é ${formatBrl(proj.regularSpentCents)}, '
        'com projeção de encerrar o mês em '
        '${formatBrl(proj.projectedRegularCents)} em despesas regulares$atypicalNote.';
    figures = [
      'Regular atual: ${formatBrl(proj.regularSpentCents)}',
      'Projeção regular: ${formatBrl(proj.projectedRegularCents)}',
      if (proj.atypicalSpentCents > 0)
        'Atípicas: ${formatBrl(proj.atypicalSpentCents)}',
    ];
  }
  // 4. Month-over-month comparison
  else if (asksComparison) {
    final cmp = monthComparison(data.transactions, targetMonth);
    final prevLabel = formatMonthYear(cmp.previousMonth);
    final direction = cmp.deltaCents >= 0 ? 'acima' : 'abaixo';
    text =
        'Em $periodLabel você gastou ${formatBrl(cmp.currentSpentCents)}, '
        'ficando ${formatBrl(cmp.deltaCents.abs())} '
        '(${formatPercent(cmp.deltaPercent.abs())}) $direction de $prevLabel '
        '(${formatBrl(cmp.previousSpentCents)}).';
    figures = [
      '$periodLabel: ${formatBrl(cmp.currentSpentCents)}',
      '$prevLabel: ${formatBrl(cmp.previousSpentCents)}',
      'Diferença: ${cmp.deltaCents >= 0 ? '+' : '−'}${formatBrl(cmp.deltaCents.abs())}',
    ];
  }
  // 5. Budgets & goals status
  else if (normQ.contains('orcamento') ||
      normQ.contains('limite') ||
      normQ.contains('meta') ||
      normQ.contains('reserva') ||
      normQ.contains('objetivo')) {
    final asksBudget =
        normQ.contains('orcamento') || normQ.contains('limite');
    final asksGoal =
        normQ.contains('meta') ||
        normQ.contains('reserva') ||
        normQ.contains('objetivo');
    final includeBudgets = asksBudget || !asksGoal;
    final includeGoals = asksGoal || !asksBudget;

    final spentByCat = {for (final c in ranking) c.category: c.cents};
    final parts = <String>[];
    figures = [];

    if (includeBudgets) {
      if (budgets.isNotEmpty) {
        final bSummary = budgets
            .map((b) {
              final used = spentByCat[b.category] ?? 0;
              final pct = b.limitCents > 0 ? used / b.limitCents : 0.0;
              final status = used > b.limitCents
                  ? ' — acima do limite'
                  : (pct >= b.alertThreshold ? ' — perto do limite' : '');
              figures.add(
                '${b.category.label}: ${formatBrl(used)} / ${formatBrl(b.limitCents)}',
              );
              return '${b.category.label}: ${formatBrl(used)} de '
                  '${formatBrl(b.limitCents)} (${formatPercent(pct, decimals: 0)}$status)';
            })
            .join('; ');
        parts.add('Orçamentos de $periodLabel: $bSummary');
      } else if (!includeGoals) {
        parts.add(
          'Você ainda não cadastrou orçamentos por categoria para $periodLabel',
        );
      }
    }

    if (includeGoals) {
      if (goals.isNotEmpty) {
        final gSummary = goals
            .map((g) {
              figures.add(
                '${g.name}: ${formatPercent(g.progress, decimals: 0)} (${formatBrl(g.currentCents)} / ${formatBrl(g.targetCents)})',
              );
              final remaining = g.isCompleted
                  ? 'concluída'
                  : 'faltam ${formatBrl(g.remainingCents)}';
              return '${g.name} em ${formatBrl(g.currentCents)} de '
                  '${formatBrl(g.targetCents)} (${formatPercent(g.progress, decimals: 0)}, $remaining)';
            })
            .join('; ');
        parts.add('Metas: $gSummary');
      } else if (!includeBudgets) {
        parts.add('Você ainda não cadastrou metas financeiras em $periodLabel');
      }
    }

    text = parts.isEmpty
        ? 'Você ainda não cadastrou orçamentos ou metas para $periodLabel.'
        : '${parts.join('. ')}.';
  }
  // 6. Top biggest individual expenses
  else if (asksTopIndividualExpenses) {
    final expenses =
        monthTxs.where((t) => t.kind == TxKind.expense).toList()
          ..sort((a, b) => b.amountCents.abs().compareTo(a.amountCents.abs()));
    if (expenses.isEmpty) {
      text = 'Não há gastos registrados em $periodLabel.';
      figures = ['Gastos: ${formatBrl(0)}'];
    } else {
      final topFive = expenses.take(5).toList(growable: false);
      final listText = topFive
          .map(
            (t) =>
                '${t.description} (${formatBrl(t.amountCents.abs())} em ${formatShortDate(t.date)})',
          )
          .join(', ');
      final topCatNote = ranking.isNotEmpty
          ? ' Por categoria, a maior foi '
                '${spendingCategoryLabel(ranking.first.category)} '
                '(${formatBrl(ranking.first.cents)}).'
          : '';
      text =
          'Em $periodLabel, seus maiores gastos individuais foram: $listText '
          '(total do mês: ${formatBrl(s.spentCents)}).$topCatNote';
      figures = [
        for (final t in topFive.take(4))
          '${t.description}: ${formatBrl(t.amountCents.abs())}',
      ];
    }
  }
  // 7. Top category question (only when no specific category was requested)
  else if (explicitCategory == null &&
      (normQ.contains('categoria') ||
          normQ.contains('pesou mais') ||
          normQ.contains('onde gastei'))) {
    if (ranking.isEmpty) {
      text = 'Não há gastos registrados em $periodLabel.';
      figures = ['Gastos: ${formatBrl(0)}'];
    } else {
      final top = ranking.first;
      final topThree = ranking
          .take(3)
          .map(
            (c) =>
                '${spendingCategoryLabel(c.category)} (${formatBrl(c.cents)}, '
                '${formatPercent(c.share)})',
          )
          .join(', ');
      text =
          'Em $periodLabel, a categoria que mais pesou foi '
          '${spendingCategoryLabel(top.category)}, com ${formatBrl(top.cents)} '
          '(${formatPercent(top.share)} dos ${formatBrl(s.spentCents)} gastos). '
          'Top 3: $topThree.';
      figures = [
        for (final c in ranking.take(3))
          '${spendingCategoryLabel(c.category)}: ${formatBrl(c.cents)} (${formatPercent(c.share)})',
      ];
    }
  }
  // 8. Leftover / balance / bill / summary question
  else if (normQ.contains('sobrou') ||
      normQ.contains('saldo') ||
      normQ.contains('sobra') ||
      normQ.contains('resumo') ||
      normQ.contains('fatura')) {
    final status = s.leftoverCents >= 0
        ? 'sobrou ${formatBrl(s.leftoverCents)}'
        : 'saiu ${formatBrl(s.leftoverCents.abs())} a mais do que entrou';
    text =
        'Em $periodLabel, entraram ${formatBrl(s.receivedCents)} em receitas e '
        'saíram ${formatBrl(s.spentCents)} em gastos — portanto $status. '
        'O saldo em contas está em ${formatBrl(s.balanceCents)} e a fatura '
        'aberta do cartão soma ${formatBrl(s.cardBillCents)}.';
    figures = [
      'Sobrou: ${formatBrl(s.leftoverCents)}',
      'Receitas: ${formatBrl(s.receivedCents)}',
      'Gastos: ${formatBrl(s.spentCents)}',
      'Fatura aberta: ${formatBrl(s.cardBillCents)}',
    ];
  }
  // 9. Specific category question
  else if (explicitCategory != null) {
    final share = ranking
        .where((c) => c.category == explicitCategory)
        .firstOrNull;
    final cents = share?.cents ?? 0;
    final pct = share?.share ?? 0.0;
    final catTxs =
        monthTxs
            .where(
              (t) =>
                  isSpending(t) &&
                  (t.splits.isNotEmpty
                      ? t.splits.any(
                          (sp) => (sp.category ?? t.category) == explicitCategory,
                        )
                      : t.category == explicitCategory),
            )
            .toList()
          ..sort((a, b) => b.amountCents.abs().compareTo(a.amountCents.abs()));
    final examples = catTxs.isEmpty
        ? ''
        : ' Principais lançamentos: '
              '${catTxs.take(3).map((t) => '${t.description} (${formatBrl(t.amountCents.abs())})').join(', ')}.';
    text =
        'Em $periodLabel, seus gastos em ${explicitCategory.label} somaram '
        '${formatBrl(cents)} (${formatPercent(pct)} do total gasto de '
        '${formatBrl(s.spentCents)}).$examples';
    figures = [
      '${explicitCategory.label}: ${formatBrl(cents)}',
      'Participação: ${formatPercent(pct)}',
      '${catTxs.length} lançamento(s)',
    ];
  }
  // 10. Merchant / establishment / tag lookup or general period summary
  else {
    final strippedQ = resolvedMonth.matchedWord == null
        ? normQ
        : normQ.replaceAll(RegExp('\\b${resolvedMonth.matchedWord}\\b'), ' ');

    final rawTokens = strippedQ
        .replaceAll(RegExp(r'\b20\d{2}\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !_stopWords.contains(w))
        .toList(growable: false);

    // Expand recognized merchant aliases (e.g. "uber" -> corrida/aplicativo,
    // "supermercado" -> supermercado/mercado, "farmacia" -> farmacia/drogaria).
    final searchTerms = <String>{};
    String? explicitAliasLabel;
    for (final tok in rawTokens) {
      final aliases = _merchantAliasGroups[tok];
      if (aliases != null) {
        explicitAliasLabel ??= tok;
        searchTerms.addAll(aliases);
      } else if (tok.length >= 4) {
        searchTerms.add(tok);
      }
    }

    final asksSpending =
        normQ.contains('gastei') ||
        normQ.contains('gasto') ||
        normQ.contains('comprei') ||
        normQ.contains('paguei');

    final matchedTxs = searchTerms.isEmpty
        ? const <Transaction>[]
        : monthTxs
              .where((t) {
                if (asksSpending && !isSpending(t)) return false;
                final descNorm = normalizeText(t.description);
                return searchTerms.any(
                  (term) =>
                      descNorm.contains(term) ||
                      t.tags.any((tag) => normalizeText(tag).contains(term)) ||
                      t.splits.any(
                        (sp) => normalizeText(sp.description).contains(term),
                      ),
                );
              })
              .toList(growable: false);

    if (matchedTxs.isNotEmpty) {
      final sum = matchedTxs.fold(
        0,
        (acc, t) =>
            acc + (t.kind == TxKind.refund ? -t.amountCents : t.amountCents.abs()),
      );
      final absSum = sum.abs();
      final itemsList = matchedTxs
          .take(3)
          .map(
            (t) =>
                '${t.description} (${formatBrl(t.amountCents.abs())} em ${formatShortDate(t.date)})',
          )
          .join(', ');
      text =
          'Em $periodLabel, encontrei ${matchedTxs.length} transação(ões) '
          'relacionada(s), somando ${formatBrl(absSum)}: $itemsList.';
      figures = [
        '${matchedTxs.length} transação(ões)',
        'Total: ${formatBrl(absSum)}',
      ];
    } else if (explicitAliasLabel != null) {
      text =
          'Não encontrei lançamentos relacionados a "$explicitAliasLabel" em '
          '$periodLabel (total de ${formatBrl(0)}).';
      figures = ['0 transações', 'Total: ${formatBrl(0)}'];
    } else {
      final top = ranking.isNotEmpty ? ranking.first : null;
      final topNote = top != null
          ? ' A maior categoria foi ${spendingCategoryLabel(top.category)} '
                '(${formatBrl(top.cents)}).'
          : '';
      text =
          'Resumo de $periodLabel: receitas de ${formatBrl(s.receivedCents)}, '
          'gastos de ${formatBrl(s.spentCents)} e saldo do mês de '
          '${formatBrl(s.leftoverCents)}.$topNote Você também pode perguntar '
          'sobre maiores gastos, categorias, estabelecimentos, orçamentos, '
          'metas, 50/30/20, projeção ou assinaturas.';
      figures = [
        'Receitas: ${formatBrl(s.receivedCents)}',
        'Gastos: ${formatBrl(s.spentCents)}',
        'Saldo do mês: ${formatBrl(s.leftoverCents)}',
      ];
    }
  }

  return AssistantMessage(
    id: replyId ?? 'pacoca-${DateTime.now().microsecondsSinceEpoch}',
    isUser: false,
    text: text,
    timestamp: now,
    periodLabel: periodLabel,
    citedFigures: List.unmodifiable(figures),
  );
}

const Set<String> _stopWords = {
  'de',
  'do',
  'da',
  'dos',
  'das',
  'no',
  'na',
  'nos',
  'nas',
  'em',
  'com',
  'por',
  'mes',
  'ano',
  'foi',
  'foram',
  'meu',
  'quanto',
  'quais',
  'qual',
  'como',
  'esta',
  'estao',
  'este',
  'esse',
  'essa',
  'para',
  'gastei',
  'gasto',
  'gastos',
  'comprei',
  'paguei',
  'minha',
  'minhas',
  'meus',
  'tenho',
  'sobre',
  'meses',
  'pacoca',
  'total',
  'valor',
  'dinheiro',
};
