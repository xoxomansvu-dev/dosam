import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'word_detail_screen.dart'; // Экран подробной информации

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arabic Bainaydak',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DictionaryHomeScreen(),
    );
  }
}

class DictionaryHomeScreen extends StatefulWidget {
  const DictionaryHomeScreen({super.key});

  @override
  State<DictionaryHomeScreen> createState() => _DictionaryHomeScreenState();
}

class _DictionaryHomeScreenState extends State<DictionaryHomeScreen> {
  List<Map<String, dynamic>> _words = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // Ваша публичная ссылка на CSV-таблицу со словами
  final String _csvUrl = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRDLEsGF5_flM17fjayqeN61kySH-Hg-DNfNbYJ7tb5qCZe2DEHxBGg9Y25F5sz0owE4PYUb84KstjA/pub?gid=0&single=true&output=csv';

  @override
  void initState() {
    super.initState();
    _loadDictionary();
  }

  Future<void> _loadDictionary() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final response = await http.get(Uri.parse(_csvUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      final parsedWords = _parseCloudDictionaryCsv(response.body);
      
      setState(() {
        _words = parsedWords;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить словарь: $e';
      });
    }
  }

  List<Map<String, dynamic>> _parseCloudDictionaryCsv(String csvText) {
    final rows = const CsvDecoder(fieldDelimiter: ',').convert(csvText);
    if (rows.isEmpty) throw const FormatException('CSV пустой');

    final headers = rows.first
        .map((value) => value.toString().replaceFirst('\uFEFF', '').trim().toLowerCase())
        .toList();

    // Обязательные колонки
    final requiredHeaders = ['volume', 'part', 'chapter', 'russian', 'arabic'];
    final indexes = <String, int>{};
    for (final header in requiredHeaders) {
      final index = headers.indexOf(header);
      if (index < 0) {
        throw FormatException('В CSV отсутствует обязательная колонка "$header"');
      }
      indexes[header] = index;
    }

    // Новые необязательные колонки (если они есть в таблице)
    const optionalHeaders = [
      'masdar', 
      'synonym', 
      'synonym_2', 
      'example_arabic', 
      'example_russian', 
      'text_title'
    ];
    for (final header in optionalHeaders) {
      final index = headers.indexOf(header);
      if (index >= 0) {
        indexes[header] = index;
      }
    }

    String field(List<dynamic> row, String name) {
      final index = indexes[name];
      if (index == null || index >= row.length) return '';
      return row[index].toString().trim();
    }

    final wordsList = <Map<String, dynamic>>[];
    for (final row in rows.skip(1)) {
      final russian = field(row, 'russian');
      final arabicCell = field(row, 'arabic');
      final volume = int.tryParse(field(row, 'volume'));
      final part = int.tryParse(field(row, 'part'));
      final chapter = int.tryParse(field(row, 'chapter'));

      if (russian.isEmpty || arabicCell.isEmpty || volume == null || part == null || chapter == null) {
        continue;
      }

      final word = <String, dynamic>{
        'bookVolume': volume,
        'bookPart': part,
        'chapter': chapter,
        'translation': russian,
        'arabic': arabicCell,
        // Заполняем новые поля из таблицы
        'masdar': field(row, 'masdar'),
        'synonym': field(row, 'synonym'),
        'synonym_2': field(row, 'synonym_2'),
        'example_arabic': field(row, 'example_arabic'),
        'example_russian': field(row, 'example_russian'),
        'text_title': field(row, 'text_title'),
      };

      wordsList.add(word);
    }

    return wordsList;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Словарь арабского языка'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDictionary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                ))
              : ListView.builder(
                  itemCount: _words.length,
                  itemBuilder: (context, index) {
                    final word = _words[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text(
                          word['arabic'] ?? '',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          textDirection: TextDirection.rtl,
                        ),
                        subtitle: Text(word['translation'] ?? ''),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        // По клику открываем детальную карточку со всей информацией
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WordDetailScreen(wordData: word),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}