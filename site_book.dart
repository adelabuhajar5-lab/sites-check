// Data handling - a direct port of the SiteBook / norm / fmt logic from
// sites_check_app.py (no UI code here).

import 'dart:typed_data';

import 'xlsx_reader.dart';

class Field {
  const Field(this.label, this.col);
  final String label;
  final int col; // zero-based column in the data sheet
}

const List<Field> kFields = [
  Field('Req No Main', 0), // A
  Field('site ID', 6), // G
  Field('Location Name', 7), // H
  Field('NCR#', 5), // F
  Field('Req Date', 1), // B
  Field('Leader', 2), // C
  Field('Vendor', 3), // D
  Field('City', 4), // E
  Field('Lat', 8), // I
  Field('Long', 9), // J
  Field('JISOW#', 10), // K
  Field('PO#', 11), // L
  Field('site Model', 12), // M
  Field('AR', 13), // N
  Field('TCAPEX', 14), // O
  Field('MSA Capex', 15), // P
  Field('Agreed CAPEX', 16), // Q
  Field('Status', 17), // R
  Field('DAS Prog%', 18), // S
  Field('TI Prog', 19), // T
];

/// The four searchable fields.
final List<Field> kInputFields = kFields.sublist(0, 4);
final List<int> kKeyCols = [for (final f in kInputFields) f.col];

const Set<int> kMoneyCols = {13, 14, 15, 16}; // AR, TCAPEX, MSA, Agreed
const int kPercentCol = 18; // DAS Prog%

String _collapse(String s) =>
    s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ');

/// Normalise a cell to a comparable string. Blank and 0 become ''.
String norm(Object? value) {
  if (value == null) return '';
  Object v = value;
  if (v is double && v.isFinite && v == v.truncateToDouble()) v = v.toInt();
  final text = _collapse(v.toString());
  return (text.isEmpty || text == '0') ? '' : text;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _withCommas(String fixed) {
  final neg = fixed.startsWith('-');
  final body = neg ? fixed.substring(1) : fixed;
  final dot = body.indexOf('.');
  final intPart = dot < 0 ? body : body.substring(0, dot);
  final frac = dot < 0 ? '' : body.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}$buf$frac';
}

String _g(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Format a raw cell value for display.
String fmt(int col, Object? value) {
  if (col == kPercentCol && value is num) {
    final pct = (value * 100 * 100).round() / 100;
    return '${_g(pct.toDouble())}%';
  }
  if (kMoneyCols.contains(col) && value is num) {
    return _withCommas(value.toStringAsFixed(2));
  }
  if (value is DateTime) {
    final d = '${_two(value.day)}/${_two(value.month)}/${value.year}';
    if (value.hour == 0 && value.minute == 0) return d;
    return '$d ${_two(value.hour)}:${_two(value.minute)}';
  }
  Object? v = value;
  if (v is double && v.isFinite && v == v.truncateToDouble()) v = v.toInt();
  if (v == null || v.toString().trim().isEmpty || v.toString().trim() == '0') {
    return kMoneyCols.contains(col) ? '0.00' : '-';
  }
  return _collapse(v.toString());
}

class SiteBook {
  SiteBook._(this.name, this.rows)
      : keys = [
          for (final r in rows) [for (final c in kKeyCols) norm(r[c])]
        ];

  /// Throws [SheetsException] when the file is not in the Sites_Check layout.
  factory SiteBook.fromBytes(String name, Uint8List bytes) {
    final raw = readDataSheet(bytes);
    if (norm(raw[0][0]).toLowerCase() != 'req no main') {
      throw SheetsException(
          "unexpected layout (cell A2 should say 'Req No Main')");
    }
    final rows = <List<Object?>>[];
    for (var i = 1; i < raw.length; i++) {
      final row = raw[i];
      if (kKeyCols.every((c) => norm(row[c]) == '')) continue;
      rows.add(row);
    }
    return SiteBook._(name, rows);
  }

  final String name;
  final List<List<Object?>> rows;
  final List<List<String>> keys;

  /// Row numbers matching every non-null filter (AND).
  List<int> match(List<String?> filters) {
    final out = <int>[];
    for (var i = 0; i < keys.length; i++) {
      var ok = true;
      for (var j = 0; j < filters.length; j++) {
        final f = filters[j];
        if (f != null && keys[i][j] != f) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(i);
    }
    return out;
  }

  /// Distinct values for input [j], given the OTHER inputs' selections.
  List<String> options(int j, List<String?> filters) {
    final found = <String>{};
    for (final k in keys) {
      if (k[j].isEmpty) continue;
      var ok = true;
      for (var i = 0; i < filters.length; i++) {
        final f = filters[i];
        if (i != j && f != null && k[i] != f) {
          ok = false;
          break;
        }
      }
      if (ok) found.add(k[j]);
    }
    final list = found.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}
