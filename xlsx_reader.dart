// Minimal .xlsx reader: returns the cached cell values of the "data" tab,
// columns A..T, starting at row 2 (the header row). Same idea as
// openpyxl(read_only=True, data_only=True) in the desktop version.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const int kHeaderRow = 2;
const int kLastCol = 20; // column T

class SheetsException implements Exception {
  SheetsException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Returns rows from row 2 downward. Element 0 is always row 2 (the header).
/// Cell values are: String, double, bool, DateTime (UTC) or null.
List<List<Object?>> readDataSheet(Uint8List bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw SheetsException('not a valid .xlsx file');
  }

  String? read(String name) {
    for (final f in archive.files) {
      if (f.isFile && f.name == name) {
        var text = utf8.decode(f.content as List<int>, allowMalformed: true);
        if (text.startsWith('\uFEFF')) text = text.substring(1);
        return text;
      }
    }
    return null;
  }

  // ---- find the "data" sheet file ----------------------------------------
  final wbXml = read('xl/workbook.xml');
  final relsXml = read('xl/_rels/workbook.xml.rels');
  if (wbXml == null || relsXml == null) {
    throw SheetsException('not a valid .xlsx file');
  }

  String? rid;
  for (final s in XmlDocument.parse(wbXml).findAllElements('sheet')) {
    final name = (s.getAttribute('name') ?? '').trim().toLowerCase();
    if (name == 'data') {
      for (final a in s.attributes) {
        if (a.name.local == 'id') rid = a.value;
      }
      break;
    }
  }
  if (rid == null) throw SheetsException("no tab named 'data'");

  String? target;
  for (final r in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
    if (r.getAttribute('Id') == rid) target = r.getAttribute('Target');
  }
  if (target == null) throw SheetsException("no tab named 'data'");
  final sheetPath =
      target.startsWith('/') ? target.substring(1) : 'xl/$target';
  final sheetXml = read(sheetPath);
  if (sheetXml == null) throw SheetsException("no tab named 'data'");

  // ---- shared strings ------------------------------------------------------
  final shared = <String>[];
  final sstXml = read('xl/sharedStrings.xml');
  if (sstXml != null) {
    for (final si in XmlDocument.parse(sstXml).findAllElements('si')) {
      final buf = StringBuffer();
      for (final child in si.childElements) {
        final n = child.name.local;
        if (n == 't') {
          buf.write(child.innerText);
        } else if (n == 'r') {
          for (final t in child.childElements) {
            if (t.name.local == 't') buf.write(t.innerText);
          }
        }
      }
      shared.add(buf.toString());
    }
  }

  // ---- which cell styles are dates ------------------------------------------
  final dateStyle = <bool>[];
  final stylesXml = read('xl/styles.xml');
  if (stylesXml != null) {
    final doc = XmlDocument.parse(stylesXml);
    final custom = <int, String>{};
    for (final n in doc.findAllElements('numFmt')) {
      final id = int.tryParse(n.getAttribute('numFmtId') ?? '');
      final code = n.getAttribute('formatCode');
      if (id != null && code != null) custom[id] = code;
    }
    final xfsParent = doc.findAllElements('cellXfs').firstOrNull;
    if (xfsParent != null) {
      for (final xf in xfsParent.childElements) {
        if (xf.name.local != 'xf') continue;
        final id = int.tryParse(xf.getAttribute('numFmtId') ?? '0') ?? 0;
        dateStyle.add(_isDateFormat(id, custom[id]));
      }
    }
  }

  // ---- read the sheet ----------------------------------------------------------
  final rows = <int, List<Object?>>{};
  var autoRow = 0;
  for (final rowEl in XmlDocument.parse(sheetXml).findAllElements('row')) {
    autoRow++;
    final rn = int.tryParse(rowEl.getAttribute('r') ?? '') ?? autoRow;
    autoRow = rn;
    if (rn < kHeaderRow) continue;

    final vals = List<Object?>.filled(kLastCol, null);
    var autoCol = -1;
    for (final c in rowEl.findElements('c')) {
      autoCol++;
      final ref = c.getAttribute('r');
      final col = ref != null ? _colIndex(ref) : autoCol;
      autoCol = col;
      if (col < 0 || col >= kLastCol) continue;
      vals[col] = _cellValue(c, shared, dateStyle);
    }
    rows[rn] = vals;
  }

  final keys = rows.keys.toList()..sort();
  final out = <List<Object?>>[
    rows[kHeaderRow] ?? List<Object?>.filled(kLastCol, null),
  ];
  for (final k in keys) {
    if (k > kHeaderRow) out.add(rows[k]!);
  }
  return out;
}

bool _isDateFormat(int id, String? code) {
  if ((id >= 14 && id <= 22) || (id >= 45 && id <= 47)) return true;
  if (code == null) return false;
  final c = code
      .replaceAll(RegExp(r'"[^"]*"'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'\\.'), '')
      .toLowerCase();
  return RegExp(r'[dmyhs]').hasMatch(c);
}

int _colIndex(String ref) {
  var n = 0;
  for (final u in ref.toUpperCase().codeUnits) {
    if (u < 65 || u > 90) break;
    n = n * 26 + (u - 64);
  }
  return n - 1;
}

Object? _cellValue(XmlElement c, List<String> shared, List<bool> dateStyle) {
  final t = c.getAttribute('t');

  if (t == 'inlineStr') {
    final inline = c.getElement('is');
    if (inline == null) return null;
    return inline.findAllElements('t').map((e) => e.innerText).join();
  }

  final vEl = c.getElement('v');
  if (vEl == null) return null;
  final raw = vEl.innerText;

  if (t == 's') {
    final i = int.tryParse(raw.trim());
    if (i == null || i < 0 || i >= shared.length) return null;
    return shared[i];
  }
  if (t == 'str') return raw;
  if (t == 'b') return raw.trim() == '1';
  if (t == 'e') return null;

  final d = double.tryParse(raw.trim());
  if (d == null) return raw;
  final s = int.tryParse(c.getAttribute('s') ?? '');
  if (s != null && s < dateStyle.length && dateStyle[s]) {
    return _serialToDate(d);
  }
  return d;
}

/// Excel serial -> DateTime (UTC). 0 / time-only values -> null (shown as "-").
DateTime? _serialToDate(double serial) {
  if (serial < 1) return null;
  final seconds = (serial * 86400).round();
  return DateTime.utc(1899, 12, 30).add(Duration(seconds: seconds));
}
