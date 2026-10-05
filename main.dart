import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'search_box.dart';
import 'site_book.dart';

// stc-style colours (change here to re-colour the whole app)
const Color kStcPurple = Color(0xFF4F008C); // main colour
const Color kStcCoral = Color(0xFFFF375E); // accent colour
const Color kStcTint = Color(0xFFEBDDF5); // light purple for labels / selections
const Color kPageBg = Color(0xFFF5F1F9); // page background

const int _latCol = 8; // column I
const int _longCol = 9; // column J

void main() => runApp(const SitesCheckApp());

class SitesCheckApp extends StatelessWidget {
  const SitesCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sites Check',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kStcPurple).copyWith(
          primary: kStcPurple,
          onPrimary: Colors.white,
          secondary: kStcCoral,
          onSecondary: Colors.white,
          primaryContainer: kStcTint,
          onPrimaryContainer: kStcPurple,
        ),
        scaffoldBackgroundColor: kPageBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kStcPurple,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SiteBook> _books = [];
  int _bookIndex = 0;
  List<int> _matches = [];
  int _matchI = 0;
  bool _loading = false;
  String _status = 'Tap "Add Excel Files" to load your Sites Check workbook(s).';

  final List<GlobalKey<SearchBoxState>> _boxKeys =
      List.generate(kInputFields.length, (_) => GlobalKey<SearchBoxState>());

  SiteBook? get _book => _books.isEmpty ? null : _books[_bookIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  // ---- files ----------------------------------------------------------------
  Future<Directory> _storeDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'sites_files'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Load every .xlsx / .xlsm stored in the app (the "Scan Folder" of the
  /// desktop version).
  Future<void> _scan({String? selectName}) async {
    setState(() => _loading = true);
    final dir = await _storeDir();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final n = p.basename(f.path).toLowerCase();
          return !n.startsWith('~\$') &&
              (n.endsWith('.xlsx') || n.endsWith('.xlsm'));
        })
        .toList()
      ..sort((a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()));

    final books = <SiteBook>[];
    final skipped = <String>[];
    for (final f in files) {
      final name = p.basename(f.path);
      try {
        final bytes = await f.readAsBytes();
        books.add(SiteBook.fromBytes(name, bytes));
      } catch (e) {
        skipped.add('$name  -  $e');
      }
    }
    if (!mounted) return;

    setState(() {
      _books = books;
      _loading = false;
    });

    if (books.isEmpty) {
      setState(() {
        _bookIndex = 0;
        _status = skipped.isEmpty
            ? 'No Excel files yet. Tap "Add Excel Files".'
            : 'No usable Excel files found.';
      });
      _clearAll();
    } else {
      var idx = 0;
      if (selectName != null) {
        final i = books.indexWhere((b) => b.name == selectName);
        if (i >= 0) idx = i;
      }
      _selectFile(idx);
    }

    if (skipped.isNotEmpty) {
      await _info('Some files were skipped',
          'These files could not be used:\n\n${skipped.join('\n')}');
    }
  }

  Future<void> _addFiles() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm'],
        allowMultiple: true,
      );
    } catch (e) {
      await _info('Could not open files', '$e');
      return;
    }
    if (result == null) return;

    final dir = await _storeDir();
    String? first;
    for (final f in result.files) {
      final src = f.path;
      if (src == null) continue;
      final name = p.basename(f.name.isNotEmpty ? f.name : src);
      await File(src).copy(p.join(dir.path, name)); // same name = replaces
      first ??= name;
    }
    await _scan(selectName: first);
  }

  Future<void> _removeCurrent() async {
    final book = _book;
    if (book == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove workbook?'),
        content: Text('Remove "${book.name}" from the app?\n'
            'Your original file is not touched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    final dir = await _storeDir();
    final f = File(p.join(dir.path, book.name));
    if (await f.exists()) await f.delete();
    await _scan();
  }

  Future<void> _info(String title, String message) {
    if (!mounted) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _selectFile(int index) {
    if (_books.isEmpty) return;
    index %= _books.length; // Dart's % is never negative here
    setState(() {
      _bookIndex = index;
      _status = '${index + 1} of ${_books.length}  -  '
          '${_books[index].rows.length} records';
    });
    _clearAll();
  }

  // ---- searching --------------------------------------------------------------
  List<String?> _filters() => [for (final k in _boxKeys) k.currentState?.value];

  List<String> _options(int j) => _book?.options(j, _filters()) ?? <String>[];

  void _clearAll() {
    for (final k in _boxKeys) {
      k.currentState?.reset();
    }
    _onFilterChange();
  }

  void _onFilterChange() {
    final filters = _filters();
    final book = _book;
    setState(() {
      if (book != null && filters.any((f) => f != null)) {
        _matches = book.match(filters);
      } else {
        _matches = [];
      }
      _matchI = 0;
    });
  }

  void _stepMatch(int step) {
    if (_matches.length > 1) {
      setState(() => _matchI = (_matchI + step) % _matches.length);
    }
  }

  List<String> _currentValues() {
    final book = _book;
    if (book == null || _matches.isEmpty) return const [];
    final row = book.rows[_matches[_matchI]];
    return [for (final f in kFields) fmt(f.col, row[f.col])];
  }

  double? _toCoord(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
    return null;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// Opens Google Maps with a pin on the Lat / Long of the selected record.
  Future<void> _openMap() async {
    final book = _book;
    if (book == null || _matches.isEmpty) return;
    final row = book.rows[_matches[_matchI]];
    final lat = _toCoord(row[_latCol]);
    final lng = _toCoord(row[_longCol]);
    if (lat == null ||
        lng == null ||
        (lat == 0 && lng == 0) ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      _snack('This record has no valid Lat / Long.');
      return;
    }
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) _snack('Could not open Google Maps.');
  }

  Future<void> _copyResult() async {
    final values = _currentValues();
    if (values.isEmpty) return;
    final text = [
      for (var i = 0; i < kFields.length; i++) '${kFields[i].label}\t${values[i]}'
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Result copied to the clipboard.')),
    );
  }

  // ---- UI ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sites Check',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 720;
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    const SizedBox(height: 8),
                    _workbookRow(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(_status,
                          style: TextStyle(color: Theme.of(context).hintColor)),
                    ),
                    _searchCard(wide),
                    const SizedBox(height: 10),
                    _resultCard(wide),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _topBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading ? null : _addFiles,
                icon: const Icon(Icons.upload_file),
                label: const Text('Add Excel Files'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _scan(),
              icon: const Icon(Icons.refresh),
              label: const Text('Scan'),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _workbookRow() {
    final hasBooks = _books.isNotEmpty;
    final multi = _books.length > 1;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous workbook',
          onPressed: multi ? () => _selectFile(_bookIndex - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: DropdownButton<int>(
            isExpanded: true,
            value: hasBooks ? _bookIndex : null,
            hint: const Text('Workbook'),
            items: [
              for (var i = 0; i < _books.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(_books[i].name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: hasBooks ? (i) => _selectFile(i ?? 0) : null,
          ),
        ),
        IconButton(
          tooltip: 'Next workbook',
          onPressed: multi ? () => _selectFile(_bookIndex + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: 'Remove this workbook',
          onPressed: hasBooks ? _removeCurrent : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _searchCard(bool wide) {
    final boxes = <Widget>[
      for (var j = 0; j < kInputFields.length; j++)
        SearchBox(
          key: _boxKeys[j],
          label: kInputFields[j].label,
          getOptions: () => _options(j),
          onChanged: _onFilterChange,
        ),
    ];

    Widget body;
    if (wide) {
      body = Column(children: [
        for (var r = 0; r < boxes.length; r += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: boxes[r]),
              const SizedBox(width: 12),
              Expanded(
                  child: r + 1 < boxes.length ? boxes[r + 1] : const SizedBox()),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ]);
    } else {
      body = Column(children: [
        for (final b in boxes) ...[b, const SizedBox(height: 10)],
      ]);
    }

    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Search',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: kStcPurple)),
            Text('Type part of a value, then pick it from the list.',
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            body,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear All'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(bool wide) {
    final theme = Theme.of(context);
    final n = _matches.length;
    final values = _currentValues();

    Widget header;
    if (n == 0) {
      header = Text(
        _book == null
            ? 'Add an Excel file to get started.'
            : 'Pick a value above to see the record.',
        style: TextStyle(color: theme.hintColor),
      );
    } else {
      header = Row(
        children: [
          IconButton(
            onPressed: n > 1 ? () => _stepMatch(-1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              n == 1 ? '1 matching record' : 'Record ${_matchI + 1} of $n',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: n > 1 ? () => _stepMatch(1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton.icon(
            onPressed: _copyResult,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ],
      );
    }

    Widget fields = const SizedBox.shrink();
    if (values.isNotEmpty) {
      Widget row(int i) => _FieldRow(label: kFields[i].label, value: values[i]);
      if (wide) {
        fields = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: [for (var i = 0; i < 10; i++) row(i)])),
            const SizedBox(width: 14),
            Expanded(
                child:
                    Column(children: [for (var i = 10; i < 20; i++) row(i)])),
          ],
        );
      } else {
        fields = Column(children: [for (var i = 0; i < 20; i++) row(i)]);
      }
    }

    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Result',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold, color: kStcPurple)),
                ),
                FilledButton.icon(
                  onPressed: n > 0 ? _openMap : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: kStcCoral,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.location_on, size: 20),
                  label: const Text('Open in Google Maps'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            header,
            const SizedBox(height: 8),
            fields,
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = Border.all(color: theme.colorScheme.outlineVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 112,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                color: kStcTint,
                border: border,
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: kStcPurple)),
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: border,
                ),
                child: SelectableText(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
