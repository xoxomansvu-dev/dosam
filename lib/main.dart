import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flip_card/flip_card.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BainaYadaykApp());
}

// Цветовая палитра
class AppColors {
  static const Color background = Color(0xFFF9F6ED);
  static const Color primaryGreen = Color(0xFF2C7A6B);
  static const Color lightGreenCard = Color(0xFFE2EBE5);
  static const Color lightBeigeCard = Color(0xFFF1EAD7);
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textGrey = Color(0xFF757575);
  static const Color logoGold = Color(0xFFFDB813);
}

class BainaYadaykApp extends StatelessWidget {
  const BainaYadaykApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Словарь Байна Йадайк',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          primary: AppColors.primaryGreen,
          surface: Colors.white,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.nunitoTextTheme(Theme.of(context).textTheme),
        fontFamilyFallback: [
          GoogleFonts.notoNaskhArabic().fontFamily ?? 'Noto Naskh Arabic'
        ],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppColors.textDark),
          titleTextStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ==========================================
// ВИДЖЕТ ЛОГОТИПА DOŞAM (SVG)
// ==========================================
class DosamLogoWidget extends StatelessWidget {
  final double width;
  final Color? color;

  const DosamLogoWidget({
    super.key,
    this.width = 160,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/logo_dosam.svg',
      width: width,
      fit: BoxFit.contain,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
      placeholderBuilder: (BuildContext context) => SizedBox(
        width: width,
        height: width * 0.65,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryGreen,
          ),
        ),
      ),
    );
  }
}

// ==========================================
// СЕРВИС УВЕДОМЛЕНИЙ И ОФФЛАЙН УРОКОВ
// ==========================================
class NotificationService {
  static const String keyUserName = 'user_display_name';
  static const String keyLessonStartDay = 'lesson_start_day_millis';
  static const String keyLessonTimeHour = 'lesson_time_hour';
  static const String keyLessonTimeMinute = 'lesson_time_minute';
  static const String keyNotificationsEnabled = 'notifications_enabled';

  static Future<bool> isLessonDay(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final int? startMillis = prefs.getInt(keyLessonStartDay);
    if (startMillis == null) return false;

    final startDate = DateTime.fromMillisecondsSinceEpoch(startMillis);
    final d1 = DateTime(startDate.year, startDate.month, startDate.day);
    final d2 = DateTime(date.year, date.month, date.day);
    final diffDays = d2.difference(d1).inDays;
    return diffDays % 2 == 0;
  }

  static Future<void> saveSchedule({
    required String name,
    required bool isLessonToday,
    required TimeOfDay lessonTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUserName, name.trim());

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final referenceDay =
        isLessonToday ? today : today.subtract(const Duration(days: 1));

    await prefs.setInt(keyLessonStartDay, referenceDay.millisecondsSinceEpoch);
    await prefs.setInt(keyLessonTimeHour, lessonTime.hour);
    await prefs.setInt(keyLessonTimeMinute, lessonTime.minute);
    await prefs.setBool(keyNotificationsEnabled, true);
  }

  static Future<String?> getSmartReminderMessage(
      List<dynamic> completedWords) async {
    final prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool(keyNotificationsEnabled) ?? true;
    if (!enabled) return null;

    final String name = prefs.getString(keyUserName) ?? '';
    final int? hour = prefs.getInt(keyLessonTimeHour);
    final int? minute = prefs.getInt(keyLessonTimeMinute);
    final now = DateTime.now();

    final bool todayLesson = await isLessonDay(now);
    final bool tomorrowLesson =
        await isLessonDay(now.add(const Duration(days: 1)));

    final timeStr = hour != null
        ? '${hour.toString().padLeft(2, '0')}:${(minute ?? 0).toString().padLeft(2, '0')}'
        : '18:00';

    if (todayLesson) {
      return '${name.isNotEmpty ? "$name, с" : "С"}егодня урок в $timeStr! Пройдите 60-секундный блиц, чтобы разогреть память перед занятием.';
    } else if (tomorrowLesson) {
      return '${name.isNotEmpty ? "$name, з" : "З"}автра оффлайн-урок в $timeStr. Уделите 5 минут повторению пройденных карточек!';
    } else if (completedWords.isNotEmpty) {
      final w = completedWords.first;
      return 'Слово дня: ${w['arabic']} — ${w['translation']}';
    }
    return null;
  }
}

// ==========================================
// АНИМИРОВАННАЯ ЗАСТАВКА (SPLASH SCREEN)
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();

    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => const MainScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryGreen,
      body: Center(
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: const Hero(
              tag: 'dosam_logo',
              child: Material(
                color: Colors.transparent,
                child: DosamLogoWidget(
                  width: 220,
                  color: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ГЛАВНЫЙ ЭКРАН И НАВИГАЦИЯ
// ==========================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static late MainScreenState instance;

  @override
  State<MainScreen> createState() {
    instance = MainScreenState();
    return instance;
  }
}

class MainScreenState extends State<MainScreen> {
  static const String _dictionaryCsvUrl =
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vRDLEsGF5_flM17fjayqeN61kySH-Hg-DNfNbYJ7tb5qCZe2DEHxBGg9Y25F5sz0owE4PYUb84KstjA/pub?gid=0&single=true&output=csv';
  static const String _dialogsCsvUrl =
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vQ-3H7rxxqgcIcpbsVY8GtIzcvv3_q1aZ5l08SG4DjHbPGPMaORLBQmXWlAhgRONZ1fNkrzPi_XAZD3/pub?gid=0&single=true&output=csv';
  static const String _appsScriptUrl =
      'https://script.google.com/macros/s/AKfycby3yUQiYdqrYv3PyUMNMSLqN9hkRVy69tt51eenMHWqPV3YhnZpLrBdOQ1qiegtbiuN/exec';

  List<dynamic> allWords = [];
  List<dynamic> displayedWords = [];
  List<dynamic> allDialogs = [];

  Set<String> knownPlurals = {};
  Set<String> completedTextTitles = {};
  String searchQuery = '';
  bool isSyncingData = false;
  int totalWordsLearned = 0;
  bool isAdmin = false;
  String userName = '';

  Set<int> selectedVolumes = {1};
  Set<int> selectedParts = {1};
  Set<int> selectedChapters = {1};
  Set<String> selectedDialogTitles = {};
  List<String> availableDialogTitles = [];

  int _currentIndex = 0;
  static final FlutterTts flutterTts = FlutterTts();
  bool _isTTSInitialized = false;

  static final enc.Key _encKey = enc.Key.fromUtf8(
    'BaynaYadaykSecretKey12345678901234'.padRight(32, '0').substring(0, 32),
  );
  static final enc.IV _encIv = enc.IV.fromLength(16);

  @override
  void initState() {
    super.initState();
    MainScreen.instance = this;
    _initTts();
    _loadAllData();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      totalWordsLearned = prefs.getInt('total_words_learned') ?? 0;
      isAdmin = prefs.getBool('is_admin') ?? false;
      userName = prefs.getString(NotificationService.keyUserName) ?? '';
      completedTextTitles =
          (prefs.getStringList('completed_text_titles') ?? []).toSet();
    });

    if (userName.isEmpty && !prefs.containsKey('onboarding_shown')) {
      await prefs.setBool('onboarding_shown', true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showUserSetupDialog();
      });
    }
  }

  void _markTextAsCompleted(String textTitle) async {
    final clean = textTitle.trim();
    if (clean.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    completedTextTitles.add(clean);
    await prefs.setStringList(
        'completed_text_titles', completedTextTitles.toList());
    setState(() {});
  }

  void _showUserSetupDialog() {
    final nameCtrl = TextEditingController(text: userName);
    bool isToday = true;
    TimeOfDay selectedTime = const TimeOfDay(hour: 18, minute: 0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Добро пожаловать!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Как к вам обращаться?'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'Ваше имя',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Когда ближайший оффлайн-урок?'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Сегодня')),
                          selected: isToday,
                          selectedColor: AppColors.lightGreenCard,
                          onSelected: (val) =>
                              setDialogState(() => isToday = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Завтра')),
                          selected: !isToday,
                          selectedColor: AppColors.lightGreenCard,
                          onSelected: (val) =>
                              setDialogState(() => isToday = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Время начала занятия:'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (t != null) {
                        setDialogState(() => selectedTime = t);
                      }
                    },
                    icon: const Icon(Icons.access_time,
                        color: AppColors.primaryGreen),
                    label: Text(
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  await NotificationService.saveSchedule(
                    name: nameCtrl.text,
                    isLessonToday: isToday,
                    lessonTime: selectedTime,
                  );
                  setState(() {
                    userName = nameCtrl.text.trim();
                  });
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen),
                child: const Text('Сохранить'),
              )
            ],
          );
        },
      ),
    );
  }

  void _initTts() async {
    if (!kIsWeb && Platform.isIOS) {
      await flutterTts.setSharedInstance(true);
      await flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }
    await flutterTts.setLanguage("ar-SA");
    if (kIsWeb) {
      await flutterTts.setSpeechRate(0.9);
    } else {
      await flutterTts.setSpeechRate(0.5);
    }
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  static Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await flutterTts.stop();
      await flutterTts.speak(text);
    }
  }

  void _onTouchStart() {
    if (!_isTTSInitialized) {
      _initializeTTS();
    }
  }

  Future<void> _initializeTTS() async {
    try {
      await flutterTts.setLanguage("ar-SA");
      if (kIsWeb) {
        await flutterTts.setSpeechRate(0.9);
      } else {
        await flutterTts.setSpeechRate(0.5);
      }
      await flutterTts.speak('');
      setState(() {
        _isTTSInitialized = true;
      });
    } catch (e) {
      print('Ошибка инициализации TTS: $e');
    }
  }

  Future<void> _loadAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? savedWords = prefs.getString('user_dictionary');
      if (savedWords != null) {
        allWords = List<dynamic>.from(json.decode(savedWords)['words']);
      } else {
        try {
          final String response =
              await rootBundle.loadString('assets/bainayadak_words.json');
          allWords = List<dynamic>.from(json.decode(response)['words']);
        } catch (_) {}
      }

      final String? savedDialogs = prefs.getString('user_dialogs');
      if (savedDialogs != null) {
        allDialogs = List<dynamic>.from(json.decode(savedDialogs)['dialogs']);
      }

      setState(() {
        _refreshData();
      });

      final bool hasSyncedOnce = prefs.getBool('has_synced_once') ?? false;
      if (!hasSyncedOnce || allWords.isEmpty) {
        await syncCloudData(showFeedback: false);
        await prefs.setBool('has_synced_once', true);
      }
    } catch (e) {
      print("Ошибка при локальной загрузке: $e");
    }
  }

  List<dynamic> _parseCloudDictionaryCsv(String csvText) {
    final rows = const CsvDecoder(fieldDelimiter: ',').convert(csvText);
    if (rows.isEmpty) return [];

    final headers = rows.first
        .map((value) =>
            value.toString().replaceFirst('\uFEFF', '').trim().toLowerCase())
        .toList();

    final requiredHeaders = ['volume', 'part', 'chapter', 'russian', 'arabic'];
    final indexes = <String, int>{};
    for (final header in requiredHeaders) {
      final index = headers.indexOf(header);
      if (index < 0) return [];
      indexes[header] = index;
    }

    const optionalHeaders = [
      'id',
      'masdar',
      'masdar_russian',
      'synonym',
      'synonym_2',
      'antonym',
      'antonym_russian',
      'example_arabic',
      'example_russian',
      'text_title',
      'dialog_title'
    ];
    for (final header in optionalHeaders) {
      final index = headers.indexOf(header);
      if (index >= 0) indexes[header] = index;
    }

    String field(List<dynamic> row, String name) {
      final index = indexes[name];
      if (index == null || index >= row.length) return '';
      return row[index].toString().trim();
    }

    final words = <Map<String, dynamic>>[];
    for (final row in rows.skip(1)) {
      final russian = field(row, 'russian');
      final arabicCell = field(row, 'arabic');
      final volume = int.tryParse(field(row, 'volume'));
      final part = int.tryParse(field(row, 'part'));
      final chapter = int.tryParse(field(row, 'chapter'));

      if (russian.isEmpty ||
          arabicCell.isEmpty ||
          volume == null ||
          part == null ||
          chapter == null) continue;

      final nounForms = arabicCell.split(RegExp(r'\s*[-–—]\s*'));
      final verbForms = arabicCell.split(RegExp(r'\s*[/\\]\s*'));
      final word = <String, dynamic>{
        'id': field(row, 'id'),
        'bookVolume': volume,
        'bookPart': part,
        'chapter': chapter,
        'dialogue': 1,
        'translation': russian,
        'masdar': field(row, 'masdar'),
        'masdar_ru': field(row, 'masdar_russian'),
        'synonym': field(row, 'synonym'),
        'synonym_2': field(row, 'synonym_2'),
        'antonym': field(row, 'antonym'),
        'antonym_ru': field(row, 'antonym_russian'),
        'example_arabic': field(row, 'example_arabic'),
        'example_russian': field(row, 'example_russian'),
        'text_title': field(row, 'text_title'),
        'dialog_title': field(row, 'dialog_title'),
      };

      if (nounForms.length == 2 && nounForms.every((form) => form.isNotEmpty)) {
        word.addAll({
          'arabic': nounForms[0],
          'pluralForm': nounForms[1],
          'isNoun': true
        });
      } else if (verbForms.length == 2 &&
          verbForms.every((form) => form.isNotEmpty)) {
        word.addAll({
          'arabic': verbForms[0],
          'pastForm': verbForms[0],
          'presentForm': verbForms[1],
          'isNoun': false
        });
      } else {
        word.addAll({'arabic': arabicCell, 'isNoun': true});
      }
      words.add(word);
    }
    return words;
  }

  List<dynamic> _parseCloudDialogsCsv(String csvText) {
    final rows = const CsvDecoder(fieldDelimiter: ',').convert(csvText);
    if (rows.isEmpty) return [];

    final headers = rows.first
        .map((value) =>
            value.toString().replaceFirst('\uFEFF', '').trim().toLowerCase())
        .toList();

    int getIdx(List<String> keywords) {
      for (var keyword in keywords) {
        final idx = headers.indexWhere((h) => h.contains(keyword));
        if (idx >= 0) return idx;
      }
      return -1;
    }

    final idxVolume = getIdx(['volume', 'том']);
    final idxPart = getIdx(['part', 'часть']);
    final idxChapter = getIdx(['chapter', 'глав', 'урок', 'номер']);
    final idxTitle =
        getIdx(['text_title', 'title', 'название', 'тема', 'диалог']);
    final idxJson = getIdx(['dialog_json', 'json', 'данные', 'words']);

    String field(List<dynamic> row, int index) {
      if (index < 0 || index >= row.length) return '';
      return row[index].toString().trim();
    }

    final dialogsMap = <String, Map<String, dynamic>>{};
    final bool hasHeaders =
        !RegExp(r'[\u0600-\u06FF]').hasMatch(rows.first.join(' '));
    final int startRow = hasHeaders ? 1 : 0;

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];

      int currentVolume = 1;
      int currentPart = 1;
      int currentChapter = 1;
      String currentTitle = 'Диалог 1';

      final volStr = idxVolume >= 0 ? field(row, idxVolume) : '';
      if (volStr.isNotEmpty) {
        currentVolume = int.tryParse(volStr) ?? currentVolume;
      }

      final partStr = idxPart >= 0 ? field(row, idxPart) : '';
      if (partStr.isNotEmpty) {
        currentPart = int.tryParse(partStr) ?? currentPart;
      }

      final chapStr = idxChapter >= 0 ? field(row, idxChapter) : '';
      if (chapStr.isNotEmpty) {
        currentChapter = int.tryParse(chapStr) ?? currentChapter;
        currentTitle = 'Диалог $currentChapter';
      }

      final titleStr = idxTitle >= 0 ? field(row, idxTitle) : '';
      if (titleStr.isNotEmpty) {
        currentTitle = titleStr;
      }

      final key =
          '${currentVolume}_${currentPart}_${currentChapter}_$currentTitle';

      if (!dialogsMap.containsKey(key)) {
        dialogsMap[key] = {
          'volume': currentVolume,
          'part': currentPart,
          'chapter': currentChapter,
          'title': currentTitle,
          'lines': <Map<String, dynamic>>[],
        };
      }

      final jsonStr = idxJson >= 0 ? field(row, idxJson) : '';

      if (jsonStr.isNotEmpty) {
        try {
          final parsedList = json.decode(jsonStr);
          if (parsedList is List) {
            for (var item in parsedList) {
              if (item is Map) {
                String speakerAr = item['speaker_ar']?.toString() ?? '';
                String speakerRu = item['speaker_ru']?.toString() ?? '';
                String textAr = item['text_ar']?.toString() ?? '';
                String textRu = item['text_ru']?.toString() ?? '';

                dialogsMap[key]!['lines'].add({
                  'speaker': speakerAr.isNotEmpty ? speakerAr : speakerRu,
                  'arabic': textAr,
                  'russian': textRu,
                });
              }
            }
          }
        } catch (e) {
          print('Ошибка парсинга JSON в строке $i: $e');
        }
      }
    }

    return dialogsMap.values.toList();
  }

  Future<void> syncCloudData({bool showFeedback = true}) async {
    if (isSyncingData) return;
    if (mounted) setState(() => isSyncingData = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final wordsResp = await http
          .get(Uri.parse(_dictionaryCsvUrl))
          .timeout(const Duration(seconds: 25));
      if (wordsResp.statusCode == 200) {
        final words = _parseCloudDictionaryCsv(
            utf8.decode(wordsResp.bodyBytes, allowMalformed: true));
        if (words.isNotEmpty) {
          allWords = words;
          await prefs.setString(
              'user_dictionary', json.encode({'words': words}));
        }
      }

      final dialogsResp = await http
          .get(Uri.parse(_dialogsCsvUrl))
          .timeout(const Duration(seconds: 25));
      if (dialogsResp.statusCode == 200) {
        final dialogs = _parseCloudDialogsCsv(
            utf8.decode(dialogsResp.bodyBytes, allowMalformed: true));
        if (dialogs.isNotEmpty) {
          allDialogs = dialogs;
          await prefs.setString(
              'user_dialogs', json.encode({'dialogs': dialogs}));
        }
      }

      if (mounted) {
        setState(() => _refreshData());
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Базы успешно обновлены!'),
                backgroundColor: AppColors.primaryGreen),
          );
        }
      }
    } catch (e) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Не удалось обновить базы. Проверьте интернет.'),
              backgroundColor: Colors.red),
        );
      }
      print('Ошибка синхронизации: $e');
    } finally {
      if (mounted) setState(() => isSyncingData = false);
    }
  }

  void _showSyncWarningDialog() {
    int timeLeft = 5;
    Timer? countdownTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            if (countdownTimer == null) {
              countdownTimer =
                  Timer.periodic(const Duration(seconds: 1), (timer) {
                if (timeLeft > 0) {
                  setStateSB(() {
                    timeLeft--;
                  });
                } else {
                  timer.cancel();
                }
              });
            }

            return AlertDialog(
              backgroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('Внимание!',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'При обновлении базы из облака все ваши локальные изменения сбросятся. Хотите продолжить?',
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    countdownTimer?.cancel();
                    Navigator.of(context).pop();
                  },
                  child:
                      const Text('Отмена', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: timeLeft > 0
                      ? null
                      : () {
                          countdownTimer?.cancel();
                          Navigator.of(context).pop();
                          syncCloudData(showFeedback: true);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    disabledBackgroundColor: Colors.orange.shade200,
                  ),
                  child: Text(timeLeft > 0 ? 'Да ($timeLeft)' : 'Да, обновить'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => countdownTimer?.cancel());
  }

  Future<void> _exportDictionary() async {
    try {
      final String jsonString =
          json.encode({"words": allWords, "dialogs": allDialogs});
      final encCrypter = enc.Encrypter(enc.AES(_encKey));
      final encrypted = encCrypter.encrypt(jsonString, iv: _encIv);

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: 'backup.bayna',
        type: FileType.custom,
        allowedExtensions: ['bayna'],
        bytes: Uint8List.fromList(utf8.encode(encrypted.base64)),
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Резервная копия сохранена: $savedPath')),
        );
      }
    } catch (e) {
      print("Ошибка экспорта: $e");
    }
  }

  Future<void> _importDictionary() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bayna'],
        withData: true,
      );

      if (result != null) {
        final bytes = result.files.single.bytes;
        if (bytes == null) {
          throw const FormatException('Не удалось прочитать файл');
        }

        final encryptedBase64 = utf8.decode(bytes);
        final encCrypter = enc.Encrypter(enc.AES(_encKey));
        final decryptedJson = encCrypter.decrypt64(encryptedBase64, iv: _encIv);

        final data = json.decode(decryptedJson);
        final prefs = await SharedPreferences.getInstance();

        setState(() {
          if (data['words'] != null) {
            allWords = List<dynamic>.from(data['words']);
            prefs.setString(
                'user_dictionary', json.encode({'words': allWords}));
          }
          if (data['dialogs'] != null) {
            allDialogs = List<dynamic>.from(data['dialogs']);
            prefs.setString(
                'user_dialogs', json.encode({'dialogs': allDialogs}));
          }
          _refreshData();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Базы успешно импортированы!'),
                backgroundColor: AppColors.primaryGreen),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ошибка: Неверный или поврежденный файл!'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _startLearningForDialog(
      int volume, int part, int chapter, String title) {
    setState(() {
      selectedVolumes = {volume};
      selectedParts = {part};
      selectedChapters = {chapter};

      updateAvailableChaptersAndFilter();

      if (availableDialogTitles.contains(title)) {
        selectedDialogTitles = {title};
      } else {
        selectedDialogTitles.clear();
      }

      filterWords();
      _currentIndex = 1;
    });
  }

  void _updateWordLocally(
      Map<String, dynamic> oldWord, Map<String, dynamic>? newWord) async {
    int index = allWords.indexWhere((w) => w == oldWord);
    if (index != -1) {
      setState(() {
        if (newWord == null) {
          allWords.removeAt(index);
        } else {
          allWords[index] = newWord;
        }
        _refreshData();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'user_dictionary', json.encode({'words': allWords}));
    }
  }

  void _refreshData() {
    knownPlurals = allWords
        .where((w) => w['isNoun'] == true && w['pluralForm'] != null)
        .map((w) => w['pluralForm'].toString().trim())
        .toSet();
    updateAvailableChaptersAndFilter();
  }

  Set<int> getAvailableChapters() {
    return _availableValues(
      allWords.where((word) {
        final volume = _dictionaryNumber(word['bookVolume']);
        final part = _dictionaryNumber(word['bookPart']);
        return volume != null &&
            part != null &&
            selectedVolumes.contains(volume) &&
            selectedParts.contains(part);
      }),
      'chapter',
    );
  }

  Set<int> getAvailableVolumes() => _availableValues(allWords, 'bookVolume');

  Set<int> getAvailableParts() {
    return _availableValues(
      allWords.where((word) {
        final volume = _dictionaryNumber(word['bookVolume']);
        return volume != null && selectedVolumes.contains(volume);
      }),
      'bookPart',
    );
  }

  int? _dictionaryNumber(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Set<int> _availableValues(Iterable<dynamic> words, String field) {
    return words
        .map((word) => _dictionaryNumber(word[field]))
        .whereType<int>()
        .toSet();
  }

  void updateAvailableChaptersAndFilter() {
    final availableVolumes = getAvailableVolumes().toList()..sort();
    selectedVolumes
        .removeWhere((volume) => !availableVolumes.contains(volume));
    if (selectedVolumes.isEmpty && availableVolumes.isNotEmpty) {
      selectedVolumes.add(availableVolumes.first);
    }

    final availableParts = getAvailableParts().toList()..sort();
    selectedParts.removeWhere((part) => !availableParts.contains(part));
    if (selectedParts.isEmpty && availableParts.isNotEmpty) {
      selectedParts.add(availableParts.first);
    }

    final availableChapters = getAvailableChapters().toList()..sort();
    selectedChapters
        .removeWhere((chapter) => !availableChapters.contains(chapter));
    if (selectedChapters.isEmpty && availableChapters.isNotEmpty) {
      selectedChapters.add(availableChapters.first);
    }

    final titlesSet = <String>{};
    for (var w in allWords) {
      final v = _dictionaryNumber(w['bookVolume']);
      final p = _dictionaryNumber(w['bookPart']);
      final c = _dictionaryNumber(w['chapter']);
      if (v != null &&
          p != null &&
          c != null &&
          selectedVolumes.contains(v) &&
          selectedParts.contains(p) &&
          selectedChapters.contains(c)) {
        final tt = (w['text_title']?.toString() ?? '').trim();
        if (tt.isNotEmpty) titlesSet.add(tt);
      }
    }
    availableDialogTitles = titlesSet.toList()..sort();

    selectedDialogTitles
        .removeWhere((title) => !availableDialogTitles.contains(title));

    filterWords();
  }

  void filterWords() {
    final normalizedQuery = _normalizeSearchText(searchQuery);
    setState(() {
      displayedWords = allWords.where((word) {
        final volume = _dictionaryNumber(word['bookVolume']);
        final part = _dictionaryNumber(word['bookPart']);
        final chapter = _dictionaryNumber(word['chapter']);

        final tt = word['text_title']?.toString() ?? '';

        bool matchesVolume =
            volume != null && selectedVolumes.contains(volume);
        bool matchesPart = part != null && selectedParts.contains(part);
        bool matchesChapter =
            chapter != null && selectedChapters.contains(chapter);
        bool matchesDialogTitle = selectedDialogTitles.isEmpty ||
            selectedDialogTitles.contains(tt);

        bool isStandalonePlural =
            knownPlurals.contains(word['arabic'].toString().trim());

        final matchesSearch = normalizedQuery.isEmpty ||
            _normalizeSearchText((word['translation'] ?? '').toString())
                .contains(normalizedQuery) ||
            _normalizeSearchText((word['arabic'] ?? '').toString())
                .contains(normalizedQuery) ||
            _normalizeSearchText(formatArabicWord(word))
                .contains(normalizedQuery);

        return matchesVolume &&
            matchesPart &&
            matchesChapter &&
            matchesDialogTitle &&
            !isStandalonePlural &&
            matchesSearch;
      }).toList();
    });
  }

  String _normalizeSearchText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[ً-ٟ]'), '').trim();
  }

  static bool containsArabicText(String value) =>
      RegExp(r'[؀-ۿ]').hasMatch(value);

  static String formatArabicWord(dynamic word) {
    final bool isNoun = word['isNoun'] ?? true;
    if (isNoun && word['pluralForm'] != null) {
      return '${word['arabic']} - ${word['pluralForm']}';
    } else if (!isNoun &&
        word['pastForm'] != null &&
        word['presentForm'] != null) {
      return '${word['pastForm']} / ${word['presentForm']}';
    }
    return word['arabic'] ?? '';
  }

  static Future<void> showMultiSelectDialog<T>(
      BuildContext context,
      String title,
      List<T> items,
      Set<T> selectedItems,
      Function(Set<T>) onApplied) async {
    Set<T> tempSelection = Set.from(selectedItems);
    bool isApplied = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              backgroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text('Выберите $title',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () =>
                              setStateSB(() => tempSelection.addAll(items)),
                          child: const Text('Выбрать всё'),
                        ),
                        if (tempSelection.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setStateSB(() => tempSelection.clear()),
                            child: const Text('Снять всё',
                                style: TextStyle(color: Colors.redAccent)),
                          ),
                      ],
                    ),
                    const Divider(),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: items.map((item) {
                          return CheckboxListTile(
                            title: Text('$item',
                                style: const TextStyle(fontSize: 16)),
                            value: tempSelection.contains(item),
                            activeColor: AppColors.primaryGreen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            onChanged: (bool? checked) {
                              setStateSB(() {
                                if (checked == true) {
                                  tempSelection.add(item);
                                } else {
                                  tempSelection.remove(item);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: tempSelection.isEmpty
                      ? null
                      : () {
                          isApplied = true;
                          Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Применить'),
                ),
              ],
            );
          },
        );
      },
    );

    if (isApplied) onApplied(tempSelection);
  }

  Widget _buildFilterChip<T>(
    String prefix,
    List<T> items,
    Set<T> selected,
    Function(Set<T>) onChanged, {
    required double width,
  }) {
    final label = selected.length == 1
        ? '$prefix ${selected.first}'
        : '$prefix (${selected.length})';

    return SizedBox(
      width: width,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: () => showMultiSelectDialog<T>(
            context, prefix.toLowerCase(), items, selected, onChanged),
        icon: const Icon(Icons.arrow_drop_down,
            size: 20, color: AppColors.primaryGreen),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textDark),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: Colors.transparent),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppColors.lightGreenCard,
        ),
      ),
    );
  }

  void _openDictionaryEditor() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DictionaryEditorScreen(
          words: allWords,
          availableDialogTitles: availableDialogTitles,
          isAdmin: isAdmin,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        allWords = result;
        _refreshData();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'user_dictionary', json.encode({'words': allWords}));
    }
  }

  String _getAppBarTitle() {
    if (_currentIndex == 0) return '';
    if (_currentIndex == 1) return 'Заучивание';
    if (_currentIndex == 2) return 'Словарь';
    if (_currentIndex == 3) return 'Диалоги';
    return 'Профиль';
  }

  Widget _buildHomeTab() {
    final List<dynamic> wordsFromCompletedTexts = allWords.where((w) {
      final t = (w['text_title'] ?? '').toString().trim();
      return completedTextTitles.contains(t);
    }).toList();

    Map<String, dynamic>? wordOfDay;
    if (wordsFromCompletedTexts.isNotEmpty) {
      final seed = DateTime.now().day + DateTime.now().month * 31;
      final random = Random(seed);
      wordOfDay = wordsFromCompletedTexts[
          random.nextInt(wordsFromCompletedTexts.length)];
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Center(
                child: Hero(
                  tag: 'dosam_logo',
                  child: Material(
                    color: Colors.transparent,
                    child: DosamLogoWidget(
                      width: 170,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _buildHomeCard(
                      title: 'Заучивание',
                      subtitle: 'Изучайте новые слова',
                      icon: Icons.school,
                      bgColor: AppColors.primaryGreen,
                      textColor: Colors.white,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildHomeCard(
                      title: 'Словарь',
                      subtitle: 'Более ${allWords.length} слов',
                      icon: Icons.menu_book,
                      bgColor: AppColors.lightBeigeCard,
                      textColor: AppColors.textDark,
                      onTap: () => setState(() => _currentIndex = 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildHomeCard(
                      title: 'Диалоги',
                      subtitle: 'Реальные ситуации',
                      icon: Icons.forum,
                      bgColor: AppColors.lightGreenCard,
                      textColor: AppColors.textDark,
                      onTap: () => setState(() => _currentIndex = 3),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildHomeCard(
                      title: 'Профиль',
                      subtitle: 'Уведомления и прогресс',
                      icon: Icons.person,
                      bgColor: Colors.white,
                      textColor: AppColors.textDark,
                      onTap: () => setState(() => _currentIndex = 4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text('Слово дня',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (wordOfDay != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.lightBeigeCard,
                        radius: 24,
                        child: IconButton(
                          icon: const Icon(Icons.play_arrow_rounded,
                              color: AppColors.primaryGreen),
                          onPressed: () => speak(wordOfDay!['arabic']),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatArabicWord(wordOfDay),
                              style: GoogleFonts.notoNaskhArabic(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  height: 1.4),
                              textDirection: TextDirection.rtl,
                            ),
                            Text(
                              wordOfDay['translation'] ?? '',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 32, color: AppColors.primaryGreen),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Пройдите хотя бы один тест к любому тексту, чтобы здесь появлялось персональное «Слово дня» из ваших уроков!',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeCard(
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color bgColor,
      required Color textColor,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              backgroundColor: textColor.withOpacity(0.1),
              radius: 20,
              child: Icon(icon, color: textColor, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: textColor.withOpacity(0.8),
                        fontSize: 12,
                        height: 1.1)),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTouchStart,
      child: Scaffold(
        appBar: _currentIndex == 0
            ? null
            : AppBar(
                title: Text(_getAppBarTitle()),
                actions: _currentIndex == 2
                    ? [
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'Опции',
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          onSelected: (value) {
                            if (value == 'sync') _showSyncWarningDialog();
                            if (value == 'edit') _openDictionaryEditor();
                            if (value == 'export') _exportDictionary();
                            if (value == 'import') _importDictionary();
                          },
                          itemBuilder: (BuildContext context) {
                            return [
                              const PopupMenuItem<String>(
                                value: 'sync',
                                child: Row(
                                  children: [
                                    Icon(Icons.sync, color: Colors.orange),
                                    SizedBox(width: 12),
                                    Text('Обновить базы'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_note, color: Colors.teal),
                                    SizedBox(width: 12),
                                    Text('Редактировать словарь'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'export',
                                child: Row(
                                  children: [
                                    Icon(Icons.upload_file, color: Colors.blue),
                                    SizedBox(width: 12),
                                    Text('Экспорт баз'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'import',
                                child: Row(
                                  children: [
                                    Icon(Icons.download, color: Colors.green),
                                    SizedBox(width: 12),
                                    Text('Импорт баз'),
                                  ],
                                ),
                              ),
                            ];
                          },
                        ),
                        const SizedBox(width: 8),
                      ]
                    : null,
              ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_currentIndex == 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: TextField(
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      searchQuery = value;
                      filterWords();
                    },
                    decoration: InputDecoration(
                      hintText: 'Поиск по словам...',
                      prefixIcon: const Icon(Icons.search),
                      fillColor: Colors.white,
                      filled: true,
                      suffixIcon: searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                searchQuery = '';
                                filterWords();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              if (_currentIndex == 1 || _currentIndex == 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 8.0;
                      final filterWidth =
                          ((constraints.maxWidth - spacing * 3) / 3.5)
                              .clamp(90.0, 160.0);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildFilterChip<int>(
                              'Том',
                              getAvailableVolumes().toList()..sort(),
                              selectedVolumes,
                              (newSet) {
                                setState(() {
                                  selectedVolumes = newSet;
                                  updateAvailableChaptersAndFilter();
                                });
                              },
                              width: filterWidth,
                            ),
                            const SizedBox(width: spacing),
                            _buildFilterChip<int>(
                              'Часть',
                              getAvailableParts().toList()..sort(),
                              selectedParts,
                              (newSet) {
                                setState(() {
                                  selectedParts = newSet;
                                  updateAvailableChaptersAndFilter();
                                });
                              },
                              width: filterWidth,
                            ),
                            const SizedBox(width: spacing),
                            _buildFilterChip<int>(
                              'Глава',
                              getAvailableChapters().toList()..sort(),
                              selectedChapters,
                              (newSet) {
                                setState(() {
                                  selectedChapters = newSet;
                                  updateAvailableChaptersAndFilter();
                                });
                              },
                              width: filterWidth,
                            ),
                            if (availableDialogTitles.isNotEmpty)
                              const SizedBox(width: spacing),
                            if (availableDialogTitles.isNotEmpty)
                              _buildFilterChip<String>(
                                'Текст',
                                availableDialogTitles,
                                selectedDialogTitles,
                                (newSet) {
                                  setState(() {
                                    selectedDialogTitles = newSet;
                                    filterWords();
                                  });
                                },
                                width: filterWidth + 40,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              Expanded(
                child: _currentIndex == 0
                    ? _buildHomeTab()
                    : _currentIndex == 4
                        ? ProfileTab(
                            totalWordsLearned: totalWordsLearned,
                            isAdmin: isAdmin,
                            onAdminStatusChanged: (status) async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool('is_admin', status);
                              setState(() => isAdmin = status);
                            },
                            onProfileUpdated: () {
                              _loadStats();
                            },
                          )
                        : _currentIndex == 3
                            ? DialogsTab(
                                dialogs: allDialogs,
                                onLearnWords: _startLearningForDialog,
                                isAdmin: isAdmin,
                                allWords: allWords,
                                availableDialogTitles: availableDialogTitles,
                                onWordAdd: (newWord) async {
                                  await syncCloudData(showFeedback: false);
                                },
                              )
                            : displayedWords.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search_off_rounded,
                                            size: 64,
                                            color: Colors.grey.shade300),
                                        const SizedBox(height: 16),
                                        Text(
                                          searchQuery.trim().isNotEmpty
                                              ? 'Слова не найдены'
                                              : 'Нет слов',
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade600),
                                        ),
                                        Text(
                                          searchQuery.trim().isNotEmpty
                                              ? 'Измените поисковый запрос или фильтры'
                                              : 'Попробуйте изменить фильтры',
                                          style: TextStyle(
                                              color: Colors.grey.shade500),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  )
                                : _currentIndex == 2
                                    ? DictionaryTab(
                                        words: displayedWords,
                                        availableDialogTitles:
                                            availableDialogTitles,
                                        onWordUpdate: _updateWordLocally,
                                        isAdmin: isAdmin,
                                      )
                                    : LearningTab(
                                        words: displayedWords,
                                        allAvailableWords: allWords,
                                        onLessonCompleted: (completedText) {
                                          _markTextAsCompleted(completedText);
                                        },
                                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          backgroundColor: Colors.white,
          indicatorColor: AppColors.lightGreenCard,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: AppColors.primaryGreen),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school, color: AppColors.primaryGreen),
              label: 'Уроки',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon:
                  Icon(Icons.menu_book, color: AppColors.primaryGreen),
              label: 'Словарь',
            ),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum, color: AppColors.primaryGreen),
              label: 'Диалоги',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: AppColors.primaryGreen),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 1. РЕЖИМ СЛОВАРЯ (С КАРТОЧКАМИ)
// ==========================================
class DictionaryTab extends StatelessWidget {
  final List<dynamic> words;
  final List<String> availableDialogTitles;
  final Function(Map<String, dynamic>, Map<String, dynamic>?) onWordUpdate;
  final bool isAdmin;

  const DictionaryTab({
    super.key,
    required this.words,
    required this.availableDialogTitles,
    required this.onWordUpdate,
    required this.isAdmin,
  });

  void _editWord(BuildContext context, Map<String, dynamic> word) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => WordEditorDialog(
        existingWord: word,
        availableDialogTitles: availableDialogTitles,
        isAdmin: isAdmin,
        allWords: words,
      ),
    );
    if (result != null) {
      final action = result['action'];
      if (action == 'save') {
        onWordUpdate(word, result['word']);
      } else if (action == 'delete') {
        onWordUpdate(word, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: words.length,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemBuilder: (context, index) {
        final word = words[index];
        String displayArabic = MainScreenState.formatArabicWord(word);

        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onLongPress: () => _editWord(context, word),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WordDetailScreen(wordData: word),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: Icon(Icons.volume_up,
                        color: Colors.blue.shade400, size: 28),
                    onPressed: () => MainScreenState.speak(word['arabic']),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          displayArabic,
                          style: GoogleFonts.notoNaskhArabic(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          word['translation'] ?? '',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnagramTile {
  final String text;
  final int poolIndex;
  final bool isDistractor;

  const AnagramTile({
    required this.text,
    required this.poolIndex,
    this.isDistractor = false,
  });

  AnagramTile copyWith({int? poolIndex}) {
    return AnagramTile(
      text: text,
      poolIndex: poolIndex ?? this.poolIndex,
      isDistractor: isDistractor,
    );
  }
}

// ==========================================
// 2. РЕЖИМ ЗАУЧИВАНИЯ
// ==========================================
class LearningTab extends StatefulWidget {
  final List<dynamic> words;
  final List<dynamic> allAvailableWords;
  final Function(String) onLessonCompleted;

  const LearningTab({
    super.key,
    required this.words,
    required this.allAvailableWords,
    required this.onLessonCompleted,
  });

  @override
  State<LearningTab> createState() => _LearningTabState();
}

class _LearningTabState extends State<LearningTab> {
  List<dynamic> queue = [];
  bool isWaitingForTap = false;
  bool isAnimating = false;
  int initialCount = 0;

  String learningMode = 'ar_ru';
  String trainingSubMode = 'cards';
  bool isBlitzStarted = false;

  List<String> quizOptions = [];
  int? selectedAnswerIndex;
  bool isQuizAnswered = false;

  List<AnagramTile?> scrambledLetters = [];
  List<AnagramTile?> userLetters = [];
  List<AnagramTile> initialAnagramPool = [];
  List<AnagramTile> correctAnagramLetters = [];
  bool isAnagramSolved = false;

  int blitzScore = 0;
  int blitzSecondsLeft = 60;
  Timer? blitzTimer;
  bool isBlitzRunning = false;

  GlobalKey<FlipCardState> cardKey = GlobalKey<FlipCardState>();
  int _cardKeyCounter = 0;
  bool isFlipped = false;
  Timer? _autoNextTimer;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void didUpdateWidget(LearningTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.words != widget.words) _initSession();
  }

  @override
  void dispose() {
    _autoNextTimer?.cancel();
    blitzTimer?.cancel();
    super.dispose();
  }

  void _initSession() {
    _autoNextTimer?.cancel();
    blitzTimer?.cancel();
    if (trainingSubMode == 'audio') learningMode = 'ar_ru';
    setState(() {
      queue = _createWordQueue();

      initialCount = queue.length;
      isWaitingForTap = false;
      isAnimating = false;
      isFlipped = false;
      _cardKeyCounter++;

      _prepareQuizOptions();
      _prepareAnagrams();

      blitzScore = 0;
      blitzSecondsLeft = 60;
      isBlitzStarted = false;
      isBlitzRunning = false;
    });

    _speakCurrentAudioWord();
  }

  List<dynamic> _createWordQueue() {
    var words = List<dynamic>.from(widget.words)..shuffle();
    return words.map((word) {
      var isArToRu = false;
      if (trainingSubMode != 'anagrams') {
        isArToRu = learningMode == 'ar_ru'
            ? true
            : learningMode == 'mixed'
                ? Random().nextBool()
                : false;
      }
      return {'word': word, 'isArToRu': isArToRu};
    }).toList();
  }

  Future<void> _speakCurrentAudioWord() async {
    if (trainingSubMode != 'audio' || queue.isEmpty) return;
    await MainScreenState.speak(
        queue.first['word']['arabic']?.toString() ?? '');
  }

  void _checkAndTriggerLessonCompletion() {
    if (queue.isEmpty && widget.words.isNotEmpty) {
      final first = widget.words.first;
      final title = (first['text_title'] ?? '').toString().trim();
      if (title.isNotEmpty) {
        widget.onLessonCompleted(title);
      }
    }
  }

  void _showContextHint(dynamic currentWord, bool isArToRu) {
    Widget buildHintRow(String label, String? arabic, String? russian) {
      if ((arabic == null || arabic.isEmpty) &&
          (russian == null || russian.isEmpty)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.right),
            if (arabic != null && arabic.isNotEmpty)
              Text(arabic,
                  style: GoogleFonts.notoNaskhArabic(
                      fontSize: 24, color: AppColors.textDark, height: 1.4),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right),
            if (russian != null && russian.isNotEmpty)
              Text(russian,
                  style:
                      const TextStyle(fontSize: 16, color: AppColors.textGrey),
                  textAlign: TextAlign.right),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primaryGreen),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Информация о слове',
                style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                MainScreenState.formatArabicWord(currentWord),
                style: GoogleFonts.notoNaskhArabic(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    height: 1.4),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                currentWord['translation'] ?? '',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textGrey),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 32),
              buildHintRow(
                  'Масдар', currentWord['masdar'], currentWord['masdar_ru']),
              buildHintRow(
                  'Синонимы',
                  [currentWord['synonym'], currentWord['synonym_2']]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' ، '),
                  null),
              buildHintRow(
                  'Антоним', currentWord['antonym'], currentWord['antonym_ru']),
              if (currentWord['example_arabic'] != null &&
                  currentWord['example_arabic'].toString().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.lightBeigeCard,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Пример:',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right),
                      Text(currentWord['example_arabic'],
                          style: GoogleFonts.notoNaskhArabic(
                              fontSize: 24,
                              color: AppColors.textDark,
                              height: 1.4),
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right),
                      if (currentWord['example_russian'] != null &&
                          currentWord['example_russian'].toString().isNotEmpty)
                        Text(currentWord['example_russian'],
                            style: const TextStyle(
                                fontSize: 16, color: AppColors.textGrey),
                            textAlign: TextAlign.right),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть',
                style: TextStyle(color: AppColors.primaryGreen, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _startBlitz() {
    if (queue.isEmpty || isBlitzStarted) return;
    setState(() {
      isBlitzStarted = true;
      isBlitzRunning = true;
      blitzScore = 0;
      blitzSecondsLeft = 60;
    });
    blitzTimer?.cancel();
    blitzTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (blitzSecondsLeft > 0) {
        setState(() => blitzSecondsLeft--);
      } else {
        timer.cancel();
        setState(() => isBlitzRunning = false);
        _checkAndTriggerLessonCompletion();
      }
    });
  }

  void _prepareQuizOptions() {
    if (queue.isEmpty) return;
    final currentItem = queue.first;
    final currentWord = currentItem['word'];
    final bool isArToRu = currentItem['isArToRu'];
    final bool targetIsNoun = currentWord['isNoun'] ?? true;

    final correctAnswer = isArToRu
        ? (currentWord['translation'] ?? '').toString()
        : MainScreenState.formatArabicWord(currentWord);

    String getAnswer(dynamic word) => isArToRu
        ? (word['translation'] ?? '').toString()
        : MainScreenState.formatArabicWord(word);

    final currentTitle = (currentWord['text_title'] ?? '').toString().trim();
    final currentVol =
        int.tryParse(currentWord['bookVolume']?.toString() ?? '') ?? 1;
    final currentPart =
        int.tryParse(currentWord['bookPart']?.toString() ?? '') ?? 1;
    final currentChap =
        int.tryParse(currentWord['chapter']?.toString() ?? '') ?? 1;

    bool isGrammarMatch(dynamic word) {
      final wNoun = word['isNoun'] ?? true;
      return wNoun == targetIsNoun;
    }

    List<String> options = [correctAnswer];

    void addFromList(List<dynamic> list) {
      var shuffled = List.from(list)..shuffle();
      for (var word in shuffled) {
        if (options.length >= 4) break;
        final ans = getAnswer(word);
        if (ans.isNotEmpty && !options.contains(ans) && isGrammarMatch(word)) {
          options.add(ans);
        }
      }
    }

    if (currentTitle.isNotEmpty) {
      final inCurrentText = widget.allAvailableWords
          .where((w) =>
              (w['text_title'] ?? '').toString().trim() == currentTitle)
          .toList();
      addFromList(inCurrentText);
    }

    if (options.length < 4) {
      final inPriorLessons = widget.allAvailableWords.where((w) {
        final v = int.tryParse(w['bookVolume']?.toString() ?? '') ?? 1;
        final p = int.tryParse(w['bookPart']?.toString() ?? '') ?? 1;
        final c = int.tryParse(w['chapter']?.toString() ?? '') ?? 1;
        final t = (w['text_title'] ?? '').toString().trim();

        if (t == currentTitle) return false;
        if (v < currentVol) return true;
        if (v == currentVol && p < currentPart) return true;
        if (v == currentVol && p == currentPart && c <= currentChap) return true;
        return false;
      }).toList();
      addFromList(inPriorLessons);
    }

    if (options.length < 4) {
      addFromList(widget.allAvailableWords);
    }

    if (options.length < 4) {
      var fallback = List.from(widget.allAvailableWords)..shuffle();
      for (var w in fallback) {
        if (options.length >= 4) break;
        final ans = getAnswer(w);
        if (ans.isNotEmpty && !options.contains(ans)) {
          options.add(ans);
        }
      }
    }

    options.shuffle();
    quizOptions = options;
    selectedAnswerIndex = null;
    isQuizAnswered = false;
  }

  void _prepareAnagrams() {
    if (queue.isEmpty) return;
    final currentWord = queue.first['word'];
    final String arabic = (currentWord['arabic'] ?? '').toString();
    final correctLetters = arabic
        .replaceAll(' ', '')
        .characters
        .toList()
        .map((text) => AnagramTile(text: text, poolIndex: -1))
        .toList();
    correctAnagramLetters = correctLetters;

    final distractorCount =
        correctLetters.isEmpty ? 0 : min(3, max(2, correctLetters.length));
    final distractors = List<AnagramTile>.generate(distractorCount, (index) {
      final source = correctLetters[index % correctLetters.length];
      return AnagramTile(
        text: _withIncorrectDiacritic(source.text, index),
        poolIndex: -1,
        isDistractor: true,
      );
    });

    final tiles = [...correctLetters, ...distractors]..shuffle();
    initialAnagramPool = List<AnagramTile>.generate(
      tiles.length,
      (index) => tiles[index].copyWith(poolIndex: index),
    );
    scrambledLetters = List<AnagramTile?>.from(initialAnagramPool);
    userLetters = List<AnagramTile?>.filled(correctLetters.length, null);
    isAnagramSolved = false;
  }

  String _withIncorrectDiacritic(String grapheme, int variant) {
    const vowelMarks = <int>[
      0x064E,
      0x064F,
      0x0650,
      0x0652,
      0x064B,
      0x064C,
      0x064D
    ];
    final runes = grapheme.runes.toList();
    final existingMarkIndex =
        runes.indexWhere((rune) => vowelMarks.contains(rune));
    final existingMark =
        existingMarkIndex == -1 ? null : runes[existingMarkIndex];
    var replacementMark = vowelMarks[variant % vowelMarks.length];
    if (replacementMark == existingMark) {
      replacementMark = vowelMarks[(variant + 1) % vowelMarks.length];
    }
    if (existingMarkIndex == -1) {
      runes.add(replacementMark);
    } else {
      runes[existingMarkIndex] = replacementMark;
    }
    return String.fromCharCodes(runes);
  }

  Future<void> _incrementLearnedWordsCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt('total_words_learned') ?? 0;
    await prefs.setInt('total_words_learned', current + 1);
  }

  void _markAsKnown() async {
    if (isAnimating || isWaitingForTap) return;

    if (!isFlipped && trainingSubMode == 'cards') {
      setState(() => isAnimating = true);
      cardKey.currentState?.toggleCard();
      isFlipped = true;
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    _incrementLearnedWordsCount();

    if (mounted) {
      setState(() {
        queue.removeAt(0);
        isAnimating = false;
        isFlipped = false;
        _cardKeyCounter++;
        _prepareQuizOptions();
        _prepareAnagrams();
      });
      _checkAndTriggerLessonCompletion();
      if (queue.isNotEmpty && trainingSubMode == 'audio') {
        MainScreenState.speak(queue.first['word']['arabic']);
      }
    }
  }

  void _markAsUnknown() {
    if (isAnimating || isWaitingForTap) return;

    if (!isFlipped && trainingSubMode == 'cards') {
      cardKey.currentState?.toggleCard();
      isFlipped = true;
    }

    setState(() => isWaitingForTap = true);

    _autoNextTimer?.cancel();
    _autoNextTimer = Timer(const Duration(seconds: 3), () {
      if (isWaitingForTap && mounted) _onScreenTap();
    });
  }

  void _onScreenTap() {
    if (isWaitingForTap) {
      _autoNextTimer?.cancel();
      setState(() {
        final item = queue.removeAt(0);
        queue.add(item);
        isWaitingForTap = false;
        isFlipped = false;
        _cardKeyCounter++;
        _prepareQuizOptions();
        _prepareAnagrams();
      });
      if (queue.isNotEmpty && trainingSubMode == 'audio') {
        MainScreenState.speak(queue.first['word']['arabic']);
      }
    }
  }

  void _handleQuizAnswer(int answerIndex, int correctAnswerIndex) {
    if (isQuizAnswered) return;
    if (answerIndex < 0 || answerIndex >= quizOptions.length) return;
    final isCorrect = answerIndex == correctAnswerIndex;

    setState(() {
      selectedAnswerIndex = answerIndex;
      isQuizAnswered = true;
    });

    if (isCorrect) {
      _incrementLearnedWordsCount();
      if (trainingSubMode == 'blitz') blitzScore++;
    }

    Timer(const Duration(seconds: 1), () async {
      if (!mounted) return;

      setState(() {
        if (isCorrect || trainingSubMode == 'blitz') {
          queue.removeAt(0);
        } else {
          final item = queue.removeAt(0);
          queue.add(item);
        }
        if (trainingSubMode == 'blitz' &&
            queue.isEmpty &&
            widget.words.isNotEmpty) {
          queue = _createWordQueue();
        }
        _prepareQuizOptions();
        if (queue.isEmpty && trainingSubMode == 'blitz') blitzTimer?.cancel();
      });
      _checkAndTriggerLessonCompletion();
      await _speakCurrentAudioWord();
    });
  }

  Widget _buildAnswerOption(int index, int correctAnswerIndex) {
    final option = quizOptions[index];
    Color backgroundColor = Colors.white;
    Color foregroundColor = Colors.black87;

    if (isQuizAnswered) {
      if (index == selectedAnswerIndex) {
        final isCorrect = index == correctAnswerIndex;
        backgroundColor =
            isCorrect ? Colors.green.shade100 : Colors.red.shade100;
        foregroundColor =
            isCorrect ? Colors.green.shade900 : Colors.red.shade900;
      } else if (index == correctAnswerIndex) {
        backgroundColor = Colors.green.shade100;
        foregroundColor = Colors.green.shade900;
      }
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: isQuizAnswered
            ? null
            : () => _handleQuizAnswer(index, correctAnswerIndex),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Text(
              option,
              softWrap: true,
              textAlign: TextAlign.center,
              style: MainScreenState.containsArabicText(option)
                  ? GoogleFonts.notoNaskhArabic(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: foregroundColor,
                      height: 1.4,
                    )
                  : TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: foregroundColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlitzStartScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 64, color: AppColors.primaryGreen),
            const SizedBox(height: 16),
            const Text(
              'Блиц',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              widget.words.isEmpty
                  ? 'В выбранном разделе нет слов для тренировки.'
                  : 'За 60 секунд ответьте на как можно больше вопросов. '
                      'После окончания списка слова перемешаются и пойдут снова.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.words.isEmpty ? null : _startBlitz,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Начать'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onAnagramLetterTap(int index) {
    if (isAnagramSolved || index < 0 || index >= scrambledLetters.length) {
      return;
    }
    final tile = scrambledLetters[index];
    if (tile == null) return;

    final emptySlot = userLetters.indexWhere((slot) => slot == null);
    if (emptySlot == -1) return;

    setState(() {
      scrambledLetters[index] = null;
      userLetters[emptySlot] = tile;
    });
    _checkAnagramAnswer();
  }

  void _onAnagramInputTap(int index) {
    if (isAnagramSolved || index < 0 || index >= userLetters.length) return;
    final tile = userLetters[index];
    if (tile == null) return;

    setState(() {
      userLetters[index] = null;
      scrambledLetters[tile.poolIndex] = tile;
    });
  }

  void _resetAnagrams() {
    if (isAnagramSolved) return;
    setState(() {
      scrambledLetters = List<AnagramTile?>.from(initialAnagramPool);
      userLetters =
          List<AnagramTile?>.filled(correctAnagramLetters.length, null);
    });
  }

  void _checkAnagramAnswer() {
    if (userLetters.any((slot) => slot == null)) return;

    if (userLetters.map((tile) => tile!.text).join() !=
        correctAnagramLetters.map((tile) => tile.text).join()) {
      return;
    }

    setState(() => isAnagramSolved = true);
    _incrementLearnedWordsCount();
    _advanceAfterAnagram();
  }

  void _skipAnagram() {
    if (isAnagramSolved || queue.isEmpty) return;
    setState(() {
      userLetters = List<AnagramTile?>.from(correctAnagramLetters);
      isAnagramSolved = true;
    });
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        queue.removeAt(0);
        _prepareAnagrams();
      });
      _checkAndTriggerLessonCompletion();
    });
  }

  void _advanceAfterAnagram() {
    Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        queue.removeAt(0);
        _prepareAnagrams();
      });
      _checkAndTriggerLessonCompletion();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isBlitzWaitingToStart =
        trainingSubMode == 'blitz' && !isBlitzStarted;
    final bool isBlitzFinished =
        trainingSubMode == 'blitz' && isBlitzStarted && !isBlitzRunning;
    if ((queue.isEmpty && !isBlitzWaitingToStart) || isBlitzFinished) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 80, color: AppColors.primaryGreen),
            const SizedBox(height: 24),
            Text(
                trainingSubMode == 'blitz'
                    ? 'Блиц окончен! Счёт: $blitzScore'
                    : 'Сессия завершена',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Отличная работа!',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _initSession,
              icon: const Icon(Icons.refresh),
              label: const Text('Следующая сессия',
                  style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            )
          ],
        ),
      );
    }

    final currentItem = queue.first;
    final currentWord = currentItem['word'];
    final bool isArToRu = currentItem['isArToRu'];

    final String displayArabic = MainScreenState.formatArabicWord(currentWord);
    String frontText =
        isArToRu ? displayArabic : (currentWord['translation'] ?? '');
    String backText =
        isArToRu ? (currentWord['translation'] ?? '') : displayArabic;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildSubModeButton('Карточки', 'cards', Icons.style),
                  _buildSubModeButton('Тест', 'quiz', Icons.quiz),
                  _buildSubModeButton('Аудио', 'audio', Icons.headphones),
                  _buildSubModeButton('Анаграммы', 'anagrams', Icons.extension),
                  _buildSubModeButton('Блиц', 'blitz', Icons.bolt),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, left: 4, right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (trainingSubMode != 'blitz' &&
                    trainingSubMode != 'audio' &&
                    trainingSubMode != 'anagrams')
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreenCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: learningMode,
                        icon: const Icon(Icons.swap_horiz,
                            color: AppColors.primaryGreen, size: 20),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                            fontSize: 14),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() => learningMode = newValue);
                            _initSession();
                          }
                        },
                        items: const [
                          DropdownMenuItem(
                              value: 'ar_ru', child: Text(' Араб ➔ Рус ')),
                          DropdownMenuItem(
                              value: 'ru_ar', child: Text(' Рус ➔ Араб ')),
                          DropdownMenuItem(
                              value: 'mixed', child: Text(' Смешанный ')),
                        ],
                      ),
                    ),
                  )
                else if (trainingSubMode == 'blitz' && isBlitzStarted)
                  Chip(
                    avatar: const Icon(Icons.timer,
                        color: AppColors.primaryGreen),
                    label: Text(
                        'Осталось: ${blitzSecondsLeft}с | Счёт: $blitzScore',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: AppColors.lightGreenCard,
                  )
                else
                  const SizedBox.shrink(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreenCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Осталось: ${queue.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: trainingSubMode == 'blitz' && !isBlitzStarted
                ? _buildBlitzStartScreen()
                : trainingSubMode == 'quiz'
                    ? _buildQuizWidget(currentWord, isArToRu)
                    : trainingSubMode == 'audio'
                        ? _buildAudioWidget(currentWord)
                        : trainingSubMode == 'anagrams'
                            ? _buildAnagramsWidget(currentWord)
                            : trainingSubMode == 'blitz'
                                ? _buildQuizWidget(currentWord, isArToRu)
                                : _buildCardsWidget(
                                    frontText, backText, isArToRu, currentWord),
          ),
        ],
      ),
    );
  }

  Widget _buildSubModeButton(String title, String modeKey, IconData icon) {
    bool isSelected = trainingSubMode == modeKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          trainingSubMode = modeKey;
          if (modeKey == 'audio') learningMode = 'ar_ru';
        });
        _initSession();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textGrey),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? Colors.white : AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardsWidget(
      String frontText, String backText, bool isArToRu, dynamic currentWord) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onScreenTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SizedBox.expand(
                  child: FlipCard(
                    key: ValueKey(_cardKeyCounter),
                    flipOnTouch: !isWaitingForTap && !isAnimating,
                    onFlipDone: (isFront) => isFlipped = !isFront,
                    direction: FlipDirection.HORIZONTAL,
                    front: Card(
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      child: Container(
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Text(frontText,
                                textAlign: TextAlign.center,
                                softWrap: true,
                                style: isArToRu
                                    ? GoogleFonts.notoNaskhArabic(
                                        fontSize: 44,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textDark,
                                        height: 1.4)
                                    : const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textDark),
                                textDirection: isArToRu
                                    ? TextDirection.rtl
                                    : TextDirection.ltr),
                          ),
                        ),
                      ),
                    ),
                    back: Card(
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                            color: isWaitingForTap
                                ? Colors.orange.shade200
                                : Colors.transparent,
                            width: 2),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white,
                        ),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Text(backText,
                                textAlign: TextAlign.center,
                                softWrap: true,
                                style: isArToRu
                                    ? const TextStyle(
                                        fontSize: 32,
                                        color: AppColors.primaryGreen,
                                        fontWeight: FontWeight.bold)
                                    : GoogleFonts.notoNaskhArabic(
                                        fontSize: 44,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryGreen,
                                        height: 1.4),
                                textDirection: isArToRu
                                    ? TextDirection.ltr
                                    : TextDirection.rtl),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: CircleAvatar(
                    backgroundColor: AppColors.lightGreenCard,
                    child: IconButton(
                      icon: const Icon(Icons.volume_up,
                          color: AppColors.primaryGreen),
                      onPressed: () =>
                          MainScreenState.speak(currentWord['arabic']),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: CircleAvatar(
                    backgroundColor: AppColors.lightBeigeCard,
                    child: IconButton(
                      icon: const Icon(Icons.lightbulb_outline,
                          color: AppColors.primaryGreen),
                      onPressed: () => _showContextHint(currentWord, isArToRu),
                      tooltip: 'Подсказка (контекст)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: FilledButton.tonal(
                    onPressed: (isAnimating || isWaitingForTap)
                        ? null
                        : _markAsUnknown,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade100,
                      foregroundColor: Colors.orange.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Ещё повторить',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: FilledButton.tonal(
                    onPressed:
                        (isAnimating || isWaitingForTap) ? null : _markAsKnown,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Помню!',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuizWidget(dynamic currentWord, bool isArToRu) {
    final String question = isArToRu
        ? MainScreenState.formatArabicWord(currentWord)
        : (currentWord['translation'] ?? '').toString();
    final correctAnswer = isArToRu
        ? (currentWord['translation'] ?? '').toString()
        : MainScreenState.formatArabicWord(currentWord);
    final correctAnswerIndex = quizOptions.indexOf(correctAnswer);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            elevation: 6,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Stack(
                children: [
                  if (isArToRu)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: 'Прослушать слово',
                        icon: const Icon(Icons.volume_up,
                            color: AppColors.primaryGreen, size: 32),
                        onPressed: () =>
                            MainScreenState.speak(currentWord['arabic']),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: IconButton(
                      tooltip: 'Подсказка (контекст)',
                      icon: const Icon(Icons.lightbulb_outline,
                          color: Colors.orange, size: 32),
                      onPressed: () => _showContextHint(currentWord, isArToRu),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 48, bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            question,
                            softWrap: true,
                            style: isArToRu
                                ? GoogleFonts.notoNaskhArabic(
                                    fontSize: 38,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    height: 1.4,
                                  )
                                : const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                            textDirection: isArToRu
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Выберите правильный перевод:',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: List.generate(
              quizOptions.length,
              (index) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                child: _buildAnswerOption(index, correctAnswerIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioWidget(dynamic currentWord) {
    final correctAnswerIndex =
        quizOptions.indexOf((currentWord['translation'] ?? '').toString());

    return Column(
      children: [
        Expanded(
          child: Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.lightGreenCard,
              child: IconButton(
                tooltip: 'Повторить аудио',
                icon: const Icon(Icons.volume_up,
                    size: 40, color: AppColors.primaryGreen),
                onPressed: () => MainScreenState.speak(currentWord['arabic']),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(quizOptions.length, (index) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            child: _buildAnswerOption(
              index,
              correctAnswerIndex,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAnagramsWidget(dynamic currentWord) {
    return Column(
      children: [
        Expanded(
          child: Card(
            elevation: 6,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentWord['translation'] ?? '',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.lightGreenCard, width: 2),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        textDirection: TextDirection.rtl,
                        children: userLetters.asMap().entries.map((entry) {
                          final index = entry.key;
                          final tile = entry.value;
                          return InkWell(
                            onTap: tile == null
                                ? null
                                : () => _onAnagramInputTap(index),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 48,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tile == null
                                    ? Colors.white
                                    : AppColors.lightGreenCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.primaryGreen
                                        .withOpacity(0.5)),
                              ),
                              child: tile == null
                                  ? null
                                  : Text(
                                      tile.text,
                                      style: GoogleFonts.notoNaskhArabic(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        height: 1.4,
                                      ),
                                      textDirection: TextDirection.rtl,
                                    ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      textDirection: TextDirection.rtl,
                      children: scrambledLetters.asMap().entries.map((entry) {
                        final index = entry.key;
                        final tile = entry.value;
                        if (tile == null) {
                          return const SizedBox(width: 48, height: 56);
                        }
                        return InkWell(
                          onTap: isAnagramSolved
                              ? null
                              : () => _onAnagramLetterTap(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 48,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.lightGreenCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      AppColors.primaryGreen.withOpacity(0.3)),
                            ),
                            child: Text(
                              tile.text,
                              style: GoogleFonts.notoNaskhArabic(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                height: 1.4,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: isAnagramSolved ? null : _resetAnagrams,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Сбросить буквы'),
                    ),
                    TextButton.icon(
                      onPressed: isAnagramSolved ? null : _skipAnagram,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Пропустить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 3. ВКЛАДКА ДИАЛОГОВ (ОДНА ГЛАВА, БЕЗ ФИЛЬТРА ТЕКСТА)
// ==========================================
class DialogsTab extends StatefulWidget {
  final List<dynamic> dialogs;
  final Function(int, int, int, String) onLearnWords;
  final bool isAdmin;
  final List<dynamic> allWords;
  final List<String> availableDialogTitles;
  final Function(Map<String, dynamic>) onWordAdd;

  const DialogsTab({
    super.key,
    required this.dialogs,
    required this.onLearnWords,
    required this.isAdmin,
    required this.allWords,
    required this.availableDialogTitles,
    required this.onWordAdd,
  });

  @override
  State<DialogsTab> createState() => _DialogsTabState();
}

class _DialogsTabState extends State<DialogsTab> {
  int currentVolume = 1;
  int currentPart = 1;
  int selectedChapter = 1;

  int _safeNum(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 1;
  }

  @override
  void initState() {
    super.initState();
    _recalculateFilters();
  }

  void _recalculateFilters() {
    final availableChapters = widget.dialogs
        .where((d) =>
            _safeNum(d['volume']) == currentVolume &&
            _safeNum(d['part']) == currentPart)
        .map((d) => _safeNum(d['chapter']))
        .toSet()
        .toList()
      ..sort();

    if (!availableChapters.contains(selectedChapter) &&
        availableChapters.isNotEmpty) {
      selectedChapter = availableChapters.first;
    }
  }

  void _showSingleChapterPicker(List<int> chapters) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Выберите главу',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chapters.length,
              itemBuilder: (ctx, i) {
                final chap = chapters[i];
                final isSelected = chap == selectedChapter;
                return ListTile(
                  title: Text('Глава $chap',
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primaryGreen
                            : AppColors.textDark,
                      )),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primaryGreen)
                      : null,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onTap: () {
                    setState(() {
                      selectedChapter = chap;
                    });
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Закрыть', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableParts = widget.dialogs
        .where((d) => _safeNum(d['volume']) == currentVolume)
        .map((d) => _safeNum(d['part']))
        .toSet()
        .toList()
      ..sort();

    if (!availableParts.contains(currentPart) && availableParts.isNotEmpty) {
      currentPart = availableParts.first;
    }

    final availableChapters = widget.dialogs
        .where((d) =>
            _safeNum(d['volume']) == currentVolume &&
            _safeNum(d['part']) == currentPart)
        .map((d) => _safeNum(d['chapter']))
        .toSet()
        .toList()
      ..sort();

    if (!availableChapters.contains(selectedChapter) &&
        availableChapters.isNotEmpty) {
      selectedChapter = availableChapters.first;
    }

    final filteredDialogs = widget.dialogs.where((d) {
      final v = _safeNum(d['volume']);
      final p = _safeNum(d['part']);
      final c = _safeNum(d['chapter']);
      return v == currentVolume && p == currentPart && c == selectedChapter;
    }).toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Книга',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: 6),
              Row(
                children: [1, 2, 3, 4].map((vol) {
                  final bool isSelected = currentVolume == vol;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            currentVolume = vol;
                            _recalculateFilters();
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: isSelected
                              ? AppColors.primaryGreen
                              : AppColors.lightGreenCard,
                          foregroundColor:
                              isSelected ? Colors.white : AppColors.textDark,
                          padding: const EdgeInsets.symmetric(vertical: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('$vol',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              const Text('Часть',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: 6),
              Row(
                children: (availableParts.isEmpty ? [1, 2] : availableParts)
                    .map((part) {
                  final bool isSelected = currentPart == part;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilledButton.tonal(
                        onPressed: () {
                          setState(() {
                            currentPart = part;
                            _recalculateFilters();
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: isSelected
                              ? AppColors.primaryGreen
                              : AppColors.lightGreenCard,
                          foregroundColor:
                              isSelected ? Colors.white : AppColors.textDark,
                          padding: const EdgeInsets.symmetric(vertical: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('Часть $part',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: availableChapters.isEmpty
                      ? null
                      : () => _showSingleChapterPicker(availableChapters),
                  icon: const Icon(Icons.arrow_drop_down,
                      color: AppColors.primaryGreen),
                  label: Text(
                    'Глава $selectedChapter',
                    style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.lightGreenCard,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredDialogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.forum_outlined,
                          size: 70, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Диалоги для Главы $selectedChapter не найдены',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filteredDialogs.length,
                  itemBuilder: (context, index) {
                    final dialog = filteredDialogs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: Colors.grey.shade200)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        title: Text(dialog['title'] ?? 'Без названия',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                        subtitle: Text(
                            'Книга ${dialog['volume']} • Часть ${dialog['part']} • Глава ${dialog['chapter']}'),
                        trailing: const Icon(Icons.play_circle_fill,
                            color: AppColors.primaryGreen, size: 36),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DialogReaderScreen(
                                dialog: dialog,
                                isAdmin: widget.isAdmin,
                                allWords: widget.allWords,
                                availableDialogTitles:
                                    widget.availableDialogTitles,
                                onLearnWords: () {
                                  Navigator.pop(context);
                                  widget.onLearnWords(
                                      dialog['volume'],
                                      dialog['part'],
                                      dialog['chapter'],
                                      dialog['title'] ?? '');
                                },
                                onWordAdd: widget.onWordAdd,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ==========================================
// ЭКРАН: ЧИТАЛКА ДИАЛОГА (КНИЖНЫЙ СТИЛЬ)
// ==========================================
class DialogReaderScreen extends StatefulWidget {
  final Map<String, dynamic> dialog;
  final VoidCallback onLearnWords;
  final bool isAdmin;
  final List<dynamic> allWords;
  final List<String> availableDialogTitles;
  final Function(Map<String, dynamic>) onWordAdd;

  const DialogReaderScreen({
    super.key,
    required this.dialog,
    required this.onLearnWords,
    required this.isAdmin,
    required this.allWords,
    required this.availableDialogTitles,
    required this.onWordAdd,
  });

  @override
  State<DialogReaderScreen> createState() => _DialogReaderScreenState();
}

class _DialogReaderScreenState extends State<DialogReaderScreen> {
  bool _isPlaying = false;
  int? _currentPlayingLineIndex;
  String _fullArabicText = '';
  final List<Map<String, int>> _lineRanges = [];
  bool _isFullPlayback = false;

  @override
  void initState() {
    super.initState();
    _prepareTextAndRanges();
  }

  void _prepareTextAndRanges() {
    final lines = List<Map<String, dynamic>>.from(widget.dialog['lines'] ?? []);
    StringBuffer sb = StringBuffer();
    _lineRanges.clear();

    int currentIndex = 0;
    for (int i = 0; i < lines.length; i++) {
      String arabicLine = lines[i]['arabic'] ?? '';
      if (arabicLine.isEmpty) {
        _lineRanges.add({'start': -1, 'end': -1});
        continue;
      }
      int start = currentIndex;
      sb.write(arabicLine);
      sb.write(' . ');
      int end = sb.length - 1;
      _lineRanges.add({'start': start, 'end': end});
      currentIndex = sb.length;
    }
    _fullArabicText = sb.toString();
  }

  void _togglePlayback() async {
    if (_isPlaying) {
      await MainScreenState.flutterTts.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isFullPlayback = false;
          _currentPlayingLineIndex = null;
        });
      }
    } else {
      if (_fullArabicText.trim().isEmpty) return;
      if (mounted) {
        setState(() {
          _isPlaying = true;
          _isFullPlayback = true;
          _currentPlayingLineIndex = 0;
        });
      }

      MainScreenState.flutterTts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isFullPlayback = false;
            _currentPlayingLineIndex = null;
          });
        }
      });

      MainScreenState.flutterTts.setProgressHandler(
          (String text, int startOffset, int endOffset, String word) {
        if (!mounted || !_isFullPlayback) return;
        for (int i = 0; i < _lineRanges.length; i++) {
          final range = _lineRanges[i];
          if (range['start'] != null && range['end'] != null) {
            if (startOffset >= range['start']! &&
                startOffset <= range['end']!) {
              if (_currentPlayingLineIndex != i) {
                setState(() {
                  _currentPlayingLineIndex = i;
                });
              }
              break;
            }
          }
        }
      });
      await MainScreenState.speak(_fullArabicText);
    }
  }

  void _playSingleLine(int index, String text) async {
    await MainScreenState.flutterTts.stop();
    if (mounted) {
      setState(() {
        _isPlaying = true;
        _isFullPlayback = false;
        _currentPlayingLineIndex = index;
      });
    }
    MainScreenState.flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPlayingLineIndex = null;
        });
      }
    });
    await MainScreenState.speak(text);
  }

  void _addNewWord() async {
    final newWordTemplate = {
      "bookVolume": widget.dialog['volume'],
      "bookPart": widget.dialog['part'],
      "chapter": widget.dialog['chapter'],
      "text_title": widget.dialog['title'],
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => WordEditorDialog(
        existingWord: newWordTemplate,
        availableDialogTitles: widget.availableDialogTitles,
        isAdmin: widget.isAdmin,
        allWords: widget.allWords,
      ),
    );

    if (result != null &&
        result['action'] == 'save' &&
        result['word'] != null) {
      widget.onWordAdd(result['word']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Слово добавлено!'),
            backgroundColor: AppColors.primaryGreen));
      }
    }
  }

  void _exportPdf() {
    final dialogTitle = (widget.dialog['title'] ?? '').trim();
    final dialogVol = widget.dialog['volume'];
    final dialogPart = widget.dialog['part'];
    final dialogChap = widget.dialog['chapter'];

    var dialogWords = widget.allWords.where((w) {
      final wTt = (w['text_title']?.toString() ?? '').trim();
      return w['bookVolume'] == dialogVol &&
          w['bookPart'] == dialogPart &&
          w['chapter'] == dialogChap &&
          wTt == dialogTitle;
    }).toList();

    if (dialogWords.isEmpty) {
      dialogWords = widget.allWords.where((w) {
        return w['bookVolume'] == dialogVol &&
            w['bookPart'] == dialogPart &&
            w['chapter'] == dialogChap;
      }).toList();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfExportScreen(
          dialogTitle:
              dialogTitle.isNotEmpty ? dialogTitle : 'Глава $dialogChap',
          initialWords: dialogWords,
          allWords: widget.allWords,
          isAdmin: widget.isAdmin,
          availableDialogTitles: widget.availableDialogTitles,
          defaultVolume: dialogVol,
          defaultPart: dialogPart,
          defaultChapter: dialogChap,
          onWordCreated: widget.onWordAdd,
        ),
      ),
    );
  }

  @override
  void dispose() {
    MainScreenState.flutterTts.stop();
    MainScreenState.flutterTts.setCompletionHandler(() {});
    MainScreenState.flutterTts.setProgressHandler((text, start, end, word) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines =
        List<Map<String, dynamic>>.from(widget.dialog['lines'] ?? []);
    final title = widget.dialog['title'] ?? 'Диалог';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontSize: 18, color: AppColors.textDark)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        actions: [
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Создать PDF',
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              onPressed: _exportPdf,
            ),
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Добавить слово',
              icon: const Icon(Icons.add_circle_outline,
                  color: AppColors.primaryGreen),
              onPressed: _addNewWord,
            ),
          IconButton(
            tooltip: 'К словам',
            icon: const Icon(Icons.school, color: AppColors.primaryGreen),
            onPressed: widget.onLearnWords,
          ),
          IconButton(
            tooltip: _isPlaying && _isFullPlayback
                ? 'Остановить'
                : 'Озвучить весь диалог',
            icon: Icon(
                _isPlaying && _isFullPlayback
                    ? Icons.stop_circle_rounded
                    : Icons.volume_up_rounded,
                color: _isPlaying && _isFullPlayback
                    ? Colors.orange
                    : AppColors.primaryGreen,
                size: 28),
            onPressed: _togglePlayback,
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: lines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final line = lines[index];
          final arabic = line['arabic'] ?? '';
          final russian = line['russian'] ?? '';
          final jsonWords = line['json'];
          final speaker = line['speaker'] ?? '';

          final bool isHighlighted = _currentPlayingLineIndex == index;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isHighlighted ? AppColors.lightGreenCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHighlighted
                    ? AppColors.primaryGreen
                    : Colors.grey.shade200,
                width: isHighlighted ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (speaker.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.lightBeigeCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        speaker,
                        style: GoogleFonts.notoNaskhArabic(
                            fontSize: 16,
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                            height: 1.4),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ),
                if (jsonWords is List && jsonWords.isNotEmpty)
                  Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      textDirection: TextDirection.rtl,
                      children: jsonWords.map<Widget>((w) {
                        if (w is Map) {
                          return Tooltip(
                              message: w['ru'] ?? w['russian'] ?? '',
                              triggerMode: TooltipTriggerMode.tap,
                              textStyle: const TextStyle(
                                  fontSize: 16, color: Colors.white),
                              decoration: BoxDecoration(
                                  color: AppColors.textDark,
                                  borderRadius: BorderRadius.circular(8)),
                              child: GestureDetector(
                                onLongPress: () {
                                  _playSingleLine(
                                      index, w['ar'] ?? w['arabic'] ?? '');
                                },
                                child: Text(w['ar'] ?? w['arabic'] ?? '',
                                    style: GoogleFonts.notoNaskhArabic(
                                      fontSize: 26,
                                      color: AppColors.textDark,
                                      height: 1.4,
                                      fontWeight: FontWeight.bold,
                                    )),
                              ));
                        }
                        return Text(w.toString(),
                            style: GoogleFonts.notoNaskhArabic(
                                fontSize: 26,
                                color: AppColors.textDark,
                                height: 1.4));
                      }).toList())
                else
                  GestureDetector(
                    onTap: () {
                      _playSingleLine(index, arabic);
                    },
                    child: Text(
                      arabic,
                      style: GoogleFonts.notoNaskhArabic(
                        fontSize: 26,
                        color: AppColors.textDark,
                        height: 1.4,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 8),
                Text(
                  russian,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// ЭКРАН ЭКСПОРТА В PDF (НАТИВНЫЙ РЕНДЕР)
// ==========================================
class PdfExportScreen extends StatefulWidget {
  final String dialogTitle;
  final List<dynamic> initialWords;
  final List<dynamic> allWords;
  final bool isAdmin;
  final List<String> availableDialogTitles;
  final int? defaultVolume;
  final int? defaultPart;
  final int? defaultChapter;
  final Function(Map<String, dynamic>) onWordCreated;

  const PdfExportScreen({
    super.key,
    required this.dialogTitle,
    required this.initialWords,
    required this.allWords,
    required this.isAdmin,
    required this.availableDialogTitles,
    this.defaultVolume,
    this.defaultPart,
    this.defaultChapter,
    required this.onWordCreated,
  });

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  late List<dynamic> selectedWords;
  bool _isGenerating = false;

  static const int _wordsPerPage = 14;
  List<GlobalKey> _pageKeys = [];

  @override
  void initState() {
    super.initState();
    selectedWords = List.from(widget.initialWords);
    _rebuildPageKeys();
  }

  void _rebuildPageKeys() {
    final pageCount = max(1, (selectedWords.length / _wordsPerPage).ceil());
    _pageKeys = List.generate(pageCount, (_) => GlobalKey());
  }

  void _addMoreWords() async {
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (context) => _WordSelectionDialog(
        allWords: widget.allWords,
        alreadySelected: selectedWords,
        isAdmin: widget.isAdmin,
        availableDialogTitles: widget.availableDialogTitles,
        defaultDialogTitle: widget.dialogTitle,
        defaultVolume: widget.defaultVolume,
        defaultPart: widget.defaultPart,
        defaultChapter: widget.defaultChapter,
        onWordCreated: (newWord) {
          widget.onWordCreated(newWord);
        },
      ),
    );
    if (result != null) {
      setState(() {
        selectedWords = result;
        _rebuildPageKeys();
      });
    }
  }

  Future<void> _generateAndSharePdf() async {
    if (selectedWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Список слов пуст!')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final pdf = pw.Document();

      for (int i = 0; i < _pageKeys.length; i++) {
        final boundary = _pageKeys[i]
            .currentContext
            ?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) continue;

        final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
        final ByteData? byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) continue;

        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final pdfImage = pw.MemoryImage(pngBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(16),
            build: (context) {
              return pw.Center(
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      }

      final Uint8List bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'slova_uroka.pdf',
      );
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Текст ошибки PDF'),
            content: SelectableText('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Widget _buildPrintablePage(int pageIndex, int totalPages) {
    final start = pageIndex * _wordsPerPage;
    final end = min(start + _wordsPerPage, selectedWords.length);
    final pageWords = selectedWords.sublist(start, end);

    String volumePartChapter = '';
    if (selectedWords.isNotEmpty) {
      final first = selectedWords.first;
      final vol = first['bookVolume'];
      final part = first['bookPart'];
      final chap = first['chapter'];
      if (vol != null && chap != null) {
        volumePartChapter = 'Том $vol, Часть ${part ?? 1}, Глава $chap';
      }
    }

    Widget buildHeaderCell(String ar, String ru) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            Text(
              ar,
              style: GoogleFonts.notoNaskhArabic(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
            Text(
              ru,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    Widget buildDataCell(String text,
        {bool isArabic = false, bool isBold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          text.trim().isEmpty ? '—' : text.trim(),
          style: isArabic
              ? GoogleFonts.notoNaskhArabic(
                  fontSize: isBold ? 18 : 16,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: Colors.black87,
                  height: 1.3,
                )
              : const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          textAlign: TextAlign.center,
        ),
      );
    }

    return RepaintBoundary(
      key: _pageKeys[pageIndex],
      child: Container(
        width: 1120,
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  volumePartChapter,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const Text(
                  'СЛОВАРЬ УРОКА',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Стр. ${pageIndex + 1} из $totalPages',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                widget.dialogTitle.isNotEmpty
                    ? widget.dialogTitle
                    : 'Текст / Диалог',
                style: GoogleFonts.notoNaskhArabic(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryGreen,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(
                color: AppColors.primaryGreen, thickness: 2, height: 20),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300, width: 1),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.4),
                4: FlexColumnWidth(2.2),
              },
              children: [
                TableRow(
                  decoration:
                      const BoxDecoration(color: AppColors.primaryGreen),
                  children: [
                    buildHeaderCell('الترجمة', 'Перевод'),
                    buildHeaderCell('عكس', 'Антоним'),
                    buildHeaderCell('مرادف', 'Синоним'),
                    buildHeaderCell('مصدر', 'Масдар'),
                    buildHeaderCell('الكلمة', 'Слово'),
                  ],
                ),
                ...List.generate(pageWords.length, (index) {
                  final word = pageWords[index];
                  final isEven = index % 2 == 1;

                  final mainWord = MainScreenState.formatArabicWord(word);
                  final masdar = word['masdar']?.toString() ?? '';
                  final synonyms = [word['synonym'], word['synonym_2']]
                      .where((e) => e != null && e.toString().trim().isNotEmpty)
                      .join(' ، ');
                  final antonym = word['antonym']?.toString() ?? '';
                  final translation = word['translation']?.toString() ?? '';

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isEven ? const Color(0xFFF4F6F4) : Colors.white,
                    ),
                    children: [
                      buildDataCell(translation, isArabic: false),
                      buildDataCell(antonym, isArabic: true),
                      buildDataCell(synonyms, isArabic: true),
                      buildDataCell(masdar, isArabic: true),
                      buildDataCell(mainWord, isArabic: true, isBold: true),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _rebuildPageKeys();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Создание PDF'),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Выбрать еще слова из базы',
            onPressed: _addMoreWords,
          )
        ],
      ),
      body: Stack(
        children: [
          if (selectedWords.isNotEmpty)
            Positioned(
              left: -3000,
              top: 0,
              child: Material(
                color: Colors.white,
                child: Column(
                  children: List.generate(
                    _pageKeys.length,
                    (i) => _buildPrintablePage(i, _pageKeys.length),
                  ),
                ),
              ),
            ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.lightGreenCard,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.primaryGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Выбрано слов для PDF: ${selectedWords.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: selectedWords.length,
                  itemBuilder: (context, index) {
                    final word = selectedWords[index];
                    return ListTile(
                      title: Text(
                        MainScreenState.formatArabicWord(word),
                        style: GoogleFonts.notoNaskhArabic(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            height: 1.4),
                        textDirection: TextDirection.rtl,
                      ),
                      subtitle: Text(word['translation'] ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            selectedWords.removeAt(index);
                            _rebuildPageKeys();
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        icon: _isGenerating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.picture_as_pdf),
        label: Text(_isGenerating ? 'Генерация...' : 'Сгенерировать PDF'),
        onPressed: _isGenerating ? null : _generateAndSharePdf,
      ),
    );
  }
}

class _WordSelectionDialog extends StatefulWidget {
  final List<dynamic> allWords;
  final List<dynamic> alreadySelected;
  final bool isAdmin;
  final List<String> availableDialogTitles;
  final String? defaultDialogTitle;
  final int? defaultVolume;
  final int? defaultPart;
  final int? defaultChapter;
  final Function(Map<String, dynamic>) onWordCreated;

  const _WordSelectionDialog({
    required this.allWords,
    required this.alreadySelected,
    required this.isAdmin,
    required this.availableDialogTitles,
    this.defaultDialogTitle,
    this.defaultVolume,
    this.defaultPart,
    this.defaultChapter,
    required this.onWordCreated,
  });

  @override
  State<_WordSelectionDialog> createState() => _WordSelectionDialogState();
}

class _WordSelectionDialogState extends State<_WordSelectionDialog> {
  String query = '';
  late List<dynamic> currentSelection;

  @override
  void initState() {
    super.initState();
    currentSelection = List.from(widget.alreadySelected);
  }

  void _createNewWord() async {
    final template = <String, dynamic>{};
    if (widget.defaultVolume != null) {
      template['bookVolume'] = widget.defaultVolume;
    }
    if (widget.defaultPart != null) {
      template['bookPart'] = widget.defaultPart;
    }
    if (widget.defaultChapter != null) {
      template['chapter'] = widget.defaultChapter;
    }
    if (widget.defaultDialogTitle != null &&
        widget.defaultDialogTitle!.isNotEmpty) {
      template['text_title'] = widget.defaultDialogTitle;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => WordEditorDialog(
        existingWord: template.isNotEmpty ? template : null,
        availableDialogTitles: widget.availableDialogTitles,
        isAdmin: widget.isAdmin,
        allWords: widget.allWords,
      ),
    );

    if (result != null &&
        result['action'] == 'save' &&
        result['word'] != null) {
      final newWord = result['word'];
      widget.onWordCreated(newWord);
      setState(() {
        if (!widget.allWords.contains(newWord)) {
          widget.allWords.add(newWord);
        }
        if (!currentSelection.contains(newWord)) {
          currentSelection.add(newWord);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allWords.where((w) {
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return (w['arabic']?.toString().toLowerCase().contains(q) ?? false) ||
          (w['translation']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Добавить слова',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: _createNewWord,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Слово', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                  hintText: 'Поиск...', prefixIcon: Icon(Icons.search)),
              onChanged: (val) => setState(() => query = val),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final word = filtered[index];
                    final isSelected = currentSelection.contains(word);
                    return CheckboxListTile(
                        title: Text(MainScreenState.formatArabicWord(word),
                            style: GoogleFonts.notoNaskhArabic(
                                fontSize: 18, height: 1.4),
                            textDirection: TextDirection.rtl),
                        subtitle: Text(word['translation'] ?? ''),
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              currentSelection.add(word);
                            } else {
                              currentSelection.remove(word);
                            }
                          });
                        });
                  }),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(context, currentSelection),
            child: const Text('Готово')),
      ],
    );
  }
}

class ProfileTab extends StatefulWidget {
  final int totalWordsLearned;
  final bool isAdmin;
  final Function(bool) onAdminStatusChanged;
  final VoidCallback onProfileUpdated;

  const ProfileTab({
    super.key,
    required this.totalWordsLearned,
    required this.isAdmin,
    required this.onAdminStatusChanged,
    required this.onProfileUpdated,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  int _avatarTapCount = 0;
  Timer? _tapTimer;
  String userName = '';
  String reminderText = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(NotificationService.keyUserName) ?? '';
    final reminder = await NotificationService.getSmartReminderMessage([]);
    setState(() {
      userName = name;
      reminderText = reminder ?? '';
    });
  }

  Map<String, dynamic> _getUserRank() {
    if (widget.totalWordsLearned < 50) {
      return {"title": "Начинающий (مبتدئ)", "next": 50, "color": Colors.brown};
    }
    if (widget.totalWordsLearned < 200) {
      return {"title": "Ученик (تلميذ)", "next": 200, "color": Colors.blueGrey};
    }
    if (widget.totalWordsLearned < 500) {
      return {"title": "Студент (طالب)", "next": 500, "color": Colors.blue};
    }
    if (widget.totalWordsLearned < 1000) {
      return {"title": "Знаток (عارف)", "next": 1000, "color": Colors.purple};
    }
    return {
      "title": "Учёный (عالم)",
      "next": 5000,
      "color": Colors.amber.shade700
    };
  }

  void _onAvatarTap() {
    if (widget.isAdmin) return;

    _avatarTapCount++;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(seconds: 2), () {
      _avatarTapCount = 0;
    });

    if (_avatarTapCount >= 7) {
      _avatarTapCount = 0;
      _showPinDialog();
    }
  }

  void _showPinDialog() {
    final TextEditingController pinCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            title: const Text('Секретный доступ'),
            content: TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Введите PIN', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена',
                      style: TextStyle(color: Colors.grey))),
              FilledButton(
                onPressed: () {
                  if (pinCtrl.text == '3369') {
                    widget.onAdminStatusChanged(true);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Режим администратора включен!'),
                        backgroundColor: AppColors.primaryGreen));
                  } else {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Неверный PIN'),
                        backgroundColor: Colors.red));
                  }
                },
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen),
                child: const Text('Войти'),
              ),
            ],
          );
        });
  }

  void _editScheduleDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final nameCtrl = TextEditingController(text: userName);
    final now = DateTime.now();
    bool isToday = await NotificationService.isLessonDay(now);

    final hour = prefs.getInt(NotificationService.keyLessonTimeHour) ?? 18;
    final minute = prefs.getInt(NotificationService.keyLessonTimeMinute) ?? 0;
    TimeOfDay selectedTime = TimeOfDay(hour: hour, minute: minute);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Настройка расписания',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Имя:'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Оффлайн-урок (строго через день):'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Сегодня')),
                          selected: isToday,
                          selectedColor: AppColors.lightGreenCard,
                          onSelected: (val) =>
                              setDialogState(() => isToday = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Завтра')),
                          selected: !isToday,
                          selectedColor: AppColors.lightGreenCard,
                          onSelected: (val) =>
                              setDialogState(() => isToday = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Время начала урока:'),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (t != null) {
                        setDialogState(() => selectedTime = t);
                      }
                    },
                    icon: const Icon(Icons.access_time,
                        color: AppColors.primaryGreen),
                    label: Text(
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                onPressed: () async {
                  await NotificationService.saveSchedule(
                    name: nameCtrl.text,
                    isLessonToday: isToday,
                    lessonTime: selectedTime,
                  );
                  Navigator.pop(ctx);
                  _loadProfileData();
                  widget.onProfileUpdated();
                },
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen),
                child: const Text('Сохранить'),
              )
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rank = _getUserRank();
    final rankTitle = rank['title'].toString();
    final rankTitleSeparator = rankTitle.indexOf('(');
    final rankArabicStart = rankTitleSeparator < 0
        ? -1
        : rankTitle.indexOf(')', rankTitleSeparator + 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _onAvatarTap,
            child: CircleAvatar(
              radius: 54,
              backgroundColor: rank['color'].withOpacity(0.2),
              child: Icon(
                  widget.isAdmin ? Icons.admin_panel_settings : Icons.school,
                  size: 54,
                  color: rank['color']),
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: rankArabicStart < 0
                  ? [
                      TextSpan(
                        text: rankTitle,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: rank['color'],
                        ),
                      ),
                    ]
                  : [
                      TextSpan(
                        text: rankTitle.substring(0, rankTitleSeparator + 1),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: rank['color'],
                        ),
                      ),
                      TextSpan(
                        text: rankTitle.substring(
                          rankTitleSeparator + 1,
                          rankArabicStart,
                        ),
                        style: GoogleFonts.notoNaskhArabic(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: rank['color'],
                          height: 1.4,
                        ),
                      ),
                      TextSpan(
                        text: rankTitle.substring(rankArabicStart),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: rank['color'],
                        ),
                      ),
                    ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('График уроков',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.edit,
                          size: 20, color: AppColors.primaryGreen),
                      onPressed: _editScheduleDialog,
                      tooltip: 'Изменить расписание',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  reminderText.isNotEmpty
                      ? reminderText
                      : 'Настройте расписание для умных напоминаний перед оффлайн-уроками.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                const Text('Изучено слов',
                    style: TextStyle(fontSize: 15, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  '${widget.totalWordsLearned}',
                  style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen),
                ),
                const SizedBox(height: 8),
                Text('Следующая цель: ${rank['next']} слов',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (widget.isAdmin) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
                onPressed: () => widget.onAdminStatusChanged(false),
                icon: const Icon(Icons.exit_to_app, color: Colors.red),
                label: const Text('Выйти из админки',
                    style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red)))
          ]
        ],
      ),
    );
  }
}

// ==========================================
// ЭКРАН РЕДАКТОРА СЛОВАРЯ (СПИСОК С ФИЛЬТРАМИ)
// ==========================================
class DictionaryEditorScreen extends StatefulWidget {
  final List<dynamic> words;
  final List<String> availableDialogTitles;
  final bool isAdmin;

  const DictionaryEditorScreen({
    super.key,
    required this.words,
    required this.availableDialogTitles,
    required this.isAdmin,
  });

  @override
  State<DictionaryEditorScreen> createState() => _DictionaryEditorScreenState();
}

class _DictionaryEditorScreenState extends State<DictionaryEditorScreen> {
  late List<dynamic> editableWords;
  List<dynamic> filteredWords = [];
  String searchQuery = '';

  Set<int> selectedVolumes = {};
  Set<int> selectedParts = {};
  Set<int> selectedChapters = {};
  Set<String> selectedDialogTitles = {};
  List<String> availableDialogTitles = [];

  int? _dictNum(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  Set<int> _availableVals(Iterable<dynamic> words, String f) {
    return words.map((w) => _dictNum(w[f])).whereType<int>().toSet();
  }

  @override
  void initState() {
    super.initState();
    editableWords = List.from(widget.words);
    _recalcFilters();
  }

  void _recalcFilters() {
    final vols = _availableVals(editableWords, 'bookVolume').toList()..sort();
    selectedVolumes.removeWhere((v) => !vols.contains(v));
    if (selectedVolumes.isEmpty && vols.isNotEmpty) {
      selectedVolumes.add(vols.first);
    }

    final parts = _availableVals(
      editableWords.where((w) {
        final v = _dictNum(w['bookVolume']);
        return v != null && selectedVolumes.contains(v);
      }),
      'bookPart',
    ).toList()
      ..sort();
    selectedParts.removeWhere((p) => !parts.contains(p));
    if (selectedParts.isEmpty && parts.isNotEmpty) {
      selectedParts.add(parts.first);
    }

    final chaps = _availableVals(
      editableWords.where((w) {
        final v = _dictNum(w['bookVolume']);
        final p = _dictNum(w['bookPart']);
        return v != null &&
            p != null &&
            selectedVolumes.contains(v) &&
            selectedParts.contains(p);
      }),
      'chapter',
    ).toList()
      ..sort();
    selectedChapters.removeWhere((c) => !chaps.contains(c));
    if (selectedChapters.isEmpty && chaps.isNotEmpty) {
      selectedChapters.add(chaps.first);
    }

    final titlesSet = <String>{};
    for (var w in editableWords) {
      final v = _dictNum(w['bookVolume']);
      final p = _dictNum(w['bookPart']);
      final c = _dictNum(w['chapter']);
      if (v != null &&
          p != null &&
          c != null &&
          selectedVolumes.contains(v) &&
          selectedParts.contains(p) &&
          selectedChapters.contains(c)) {
        final tt = (w['text_title']?.toString() ?? '').trim();
        if (tt.isNotEmpty) titlesSet.add(tt);
      }
    }
    availableDialogTitles = titlesSet.toList()..sort();
    selectedDialogTitles.removeWhere((t) => !availableDialogTitles.contains(t));

    _applyFilter();
  }

  void _applyFilter() {
    final lowerQuery = searchQuery.toLowerCase().trim();
    setState(() {
      filteredWords = editableWords.where((word) {
        final volume = _dictNum(word['bookVolume']);
        final part = _dictNum(word['bookPart']);
        final chapter = _dictNum(word['chapter']);
        final tt = (word['text_title']?.toString() ?? '').trim();

        bool matchVol = selectedVolumes.isEmpty ||
            (volume != null && selectedVolumes.contains(volume));
        bool matchPart = selectedParts.isEmpty ||
            (part != null && selectedParts.contains(part));
        bool matchChap = selectedChapters.isEmpty ||
            (chapter != null && selectedChapters.contains(chapter));
        bool matchTitle =
            selectedDialogTitles.isEmpty || selectedDialogTitles.contains(tt);

        bool matchSearch = true;
        if (lowerQuery.isNotEmpty) {
          final ar = (word['arabic'] ?? '').toString().toLowerCase();
          final ru = (word['translation'] ?? '').toString().toLowerCase();
          matchSearch = ar.contains(lowerQuery) || ru.contains(lowerQuery);
        }

        return matchVol && matchPart && matchChap && matchTitle && matchSearch;
      }).toList();
    });
  }

  Widget _buildFilterChip<T>(
    String prefix,
    List<T> items,
    Set<T> selected,
    Function(Set<T>) onChanged, {
    required double width,
  }) {
    final label = selected.length == 1
        ? '$prefix ${selected.first}'
        : '$prefix (${selected.length})';

    return SizedBox(
      width: width,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: () => MainScreenState.showMultiSelectDialog<T>(
            context, prefix.toLowerCase(), items, selected, onChanged),
        icon: const Icon(Icons.arrow_drop_down,
            size: 20, color: AppColors.primaryGreen),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textDark),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: Colors.transparent),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppColors.lightGreenCard,
        ),
      ),
    );
  }

  void _openWordDialog([int? filteredIndex]) async {
    Map<String, dynamic>? wordToEdit;
    int? realIndex;

    if (filteredIndex != null) {
      wordToEdit = filteredWords[filteredIndex];
      realIndex = editableWords.indexWhere((w) => w == wordToEdit);
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => WordEditorDialog(
        existingWord: wordToEdit,
        availableDialogTitles: widget.availableDialogTitles,
        isAdmin: widget.isAdmin,
        allWords: editableWords,
      ),
    );

    if (result != null &&
        result['action'] == 'save' &&
        result['word'] != null) {
      setState(() {
        if (realIndex != null && realIndex != -1) {
          editableWords[realIndex] = result['word'];
        } else {
          editableWords.add(result['word']);
        }
        _recalcFilters();
      });
    }
  }

  void _deleteWord(int filteredIndex) {
    final wordToDelete = filteredWords[filteredIndex];
    final realIndex = editableWords.indexWhere((w) => w == wordToDelete);
    if (realIndex != -1) {
      setState(() {
        editableWords.removeAt(realIndex);
        _recalcFilters();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактор базы'),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, editableWords),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск по слову или переводу...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                searchQuery = val;
                _applyFilter();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final filterWidth =
                    ((constraints.maxWidth - spacing * 3) / 3.5)
                        .clamp(90.0, 160.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildFilterChip<int>(
                        'Том',
                        _availableVals(editableWords, 'bookVolume').toList()
                          ..sort(),
                        selectedVolumes,
                        (newSet) {
                          setState(() {
                            selectedVolumes = newSet;
                            _recalcFilters();
                          });
                        },
                        width: filterWidth,
                      ),
                      const SizedBox(width: spacing),
                      _buildFilterChip<int>(
                        'Часть',
                        _availableVals(
                          editableWords.where((w) {
                            final v = _dictNum(w['bookVolume']);
                            return v != null && selectedVolumes.contains(v);
                          }),
                          'bookPart',
                        ).toList()
                          ..sort(),
                        selectedParts,
                        (newSet) {
                          setState(() {
                            selectedParts = newSet;
                            _recalcFilters();
                          });
                        },
                        width: filterWidth,
                      ),
                      const SizedBox(width: spacing),
                      _buildFilterChip<int>(
                        'Глава',
                        _availableVals(
                          editableWords.where((w) {
                            final v = _dictNum(w['bookVolume']);
                            final p = _dictNum(w['bookPart']);
                            return v != null &&
                                p != null &&
                                selectedVolumes.contains(v) &&
                                selectedParts.contains(p);
                          }),
                          'chapter',
                        ).toList()
                          ..sort(),
                        selectedChapters,
                        (newSet) {
                          setState(() {
                            selectedChapters = newSet;
                            _recalcFilters();
                          });
                        },
                        width: filterWidth,
                      ),
                      if (availableDialogTitles.isNotEmpty)
                        const SizedBox(width: spacing),
                      if (availableDialogTitles.isNotEmpty)
                        _buildFilterChip<String>(
                          'Текст',
                          availableDialogTitles,
                          selectedDialogTitles,
                          (newSet) {
                            setState(() {
                              selectedDialogTitles = newSet;
                              _applyFilter();
                            });
                          },
                          width: filterWidth + 40,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredWords.length,
              itemBuilder: (context, index) {
                final word = filteredWords[index];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${word['arabic']} - ',
                          style: GoogleFonts.notoNaskhArabic(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                        TextSpan(
                          text: word['translation']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    softWrap: true,
                  ),
                  subtitle: Text(
                      'Том: ${word['bookVolume']} | Часть: ${word['bookPart']} | Глава: ${word['chapter']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.blue),
                          onPressed: () => _openWordDialog(index)),
                      IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _deleteWord(index)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        onPressed: () => _openWordDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Добавить слово'),
      ),
    );
  }
}

// ==========================================
// ДИАЛОГ РЕДАКТИРОВАНИЯ СЛОВА
// ==========================================
class WordEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existingWord;
  final List<String> availableDialogTitles;
  final bool isAdmin;
  final List<dynamic> allWords;

  const WordEditorDialog({
    super.key,
    this.existingWord,
    required this.availableDialogTitles,
    required this.isAdmin,
    required this.allWords,
  });

  @override
  State<WordEditorDialog> createState() => _WordEditorDialogState();
}

class _WordEditorDialogState extends State<WordEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late int volume;
  late int part;
  late int chapter;
  late bool isNoun;
  String? selectedTextTitle;
  bool isSavingToCloud = false;

  final TextEditingController arabicCtrl = TextEditingController();
  final TextEditingController translationCtrl = TextEditingController();
  final TextEditingController pluralCtrl = TextEditingController();
  final TextEditingController pastCtrl = TextEditingController();
  final TextEditingController presentCtrl = TextEditingController();

  final TextEditingController masdarCtrl = TextEditingController();
  final TextEditingController masdarRuCtrl = TextEditingController();
  final TextEditingController synonymCtrl = TextEditingController();
  final TextEditingController synonym2Ctrl = TextEditingController();
  final TextEditingController antonymCtrl = TextEditingController();
  final TextEditingController antonymRuCtrl = TextEditingController();
  final TextEditingController exampleArCtrl = TextEditingController();
  final TextEditingController exampleRuCtrl = TextEditingController();

  List<String> _dropdownTitles = [];
  List<String> _arabicWordOptions = [];

  @override
  void initState() {
    super.initState();
    final word = widget.existingWord;

    volume = _safeInt(word?['bookVolume'], 1);
    part = _safeInt(word?['bookPart'], 1);
    chapter = _safeInt(word?['chapter'], 1);
    isNoun = word?['isNoun'] ?? true;

    _dropdownTitles = ['', ...widget.availableDialogTitles];

    _arabicWordOptions = widget.allWords
        .map((w) => w['arabic']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    String existingTitle = (word?['text_title']?.toString() ?? '').trim();
    if (existingTitle.isEmpty) {
      existingTitle = (word?['dialog_title']?.toString() ?? '').trim();
    }

    if (existingTitle.isNotEmpty && !_dropdownTitles.contains(existingTitle)) {
      _dropdownTitles.add(existingTitle);
    }

    selectedTextTitle = existingTitle.isNotEmpty ? existingTitle : '';

    arabicCtrl.text = (isNoun && word?['pluralForm'] == null && word != null)
        ? (word['arabic']?.toString() ?? '')
        : (isNoun
            ? (word?['arabic']?.toString().split('-').first.trim() ?? '')
            : (word?['arabic']?.toString().split('/').first.trim() ?? ''));
    if (word != null && word.containsKey('pastForm')) {
      pastCtrl.text = word['pastForm']?.toString() ?? '';
      presentCtrl.text = word['presentForm']?.toString() ?? '';
    } else {
      arabicCtrl.text = word?['arabic']?.toString() ?? '';
    }
    translationCtrl.text = word?['translation']?.toString() ?? '';
    pluralCtrl.text = word?['pluralForm']?.toString() ?? '';

    masdarCtrl.text = word?['masdar']?.toString() ?? '';
    masdarRuCtrl.text = word?['masdar_ru']?.toString() ?? '';
    synonymCtrl.text = word?['synonym']?.toString() ?? '';
    synonym2Ctrl.text = word?['synonym_2']?.toString() ?? '';
    antonymCtrl.text = word?['antonym']?.toString() ?? '';
    antonymRuCtrl.text = word?['antonym_ru']?.toString() ?? '';
    exampleArCtrl.text = word?['example_arabic']?.toString() ?? '';
    exampleRuCtrl.text = word?['example_russian']?.toString() ?? '';
  }

  int _safeInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return defaultValue;
  }

  Map<String, dynamic> _collectWordData() {
    String baseArabic = arabicCtrl.text.trim();

    Map<String, dynamic> newWord = {
      "bookVolume": volume,
      "bookPart": part,
      "chapter": chapter,
      "dialogue": 1,
      "arabic": baseArabic,
      "translation": translationCtrl.text.trim(),
      "isNoun": isNoun,
      "text_title": selectedTextTitle,
    };

    if (widget.existingWord != null && widget.existingWord!['id'] != null) {
      newWord['id'] = widget.existingWord!['id'];
    }

    if (isNoun) {
      if (pluralCtrl.text.trim().isNotEmpty) {
        newWord["pluralForm"] = pluralCtrl.text.trim();
      }
    } else {
      if (pastCtrl.text.trim().isNotEmpty &&
          presentCtrl.text.trim().isNotEmpty) {
        newWord["pastForm"] = pastCtrl.text.trim();
        newWord["presentForm"] = presentCtrl.text.trim();
      }
    }

    if (masdarCtrl.text.trim().isNotEmpty) {
      newWord["masdar"] = masdarCtrl.text.trim();
    }
    if (masdarRuCtrl.text.trim().isNotEmpty) {
      newWord["masdar_ru"] = masdarRuCtrl.text.trim();
    }
    if (synonymCtrl.text.trim().isNotEmpty) {
      newWord["synonym"] = synonymCtrl.text.trim();
    }
    if (synonym2Ctrl.text.trim().isNotEmpty) {
      newWord["synonym_2"] = synonym2Ctrl.text.trim();
    }
    if (antonymCtrl.text.trim().isNotEmpty) {
      newWord["antonym"] = antonymCtrl.text.trim();
    }
    if (antonymRuCtrl.text.trim().isNotEmpty) {
      newWord["antonym_ru"] = antonymRuCtrl.text.trim();
    }
    if (exampleArCtrl.text.trim().isNotEmpty) {
      newWord["example_arabic"] = exampleArCtrl.text.trim();
    }
    if (exampleRuCtrl.text.trim().isNotEmpty) {
      newWord["example_russian"] = exampleRuCtrl.text.trim();
    }

    return newWord;
  }

  void _saveLocal() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, {'action': 'save', 'word': _collectWordData()});
    }
  }

  Future<void> _saveToCloud() async {
    if (!_formKey.currentState!.validate()) return;

    final wordData = _collectWordData();
    final isEdit =
        wordData.containsKey('id') && wordData['id'].toString().isNotEmpty;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение'),
        content: Text(isEdit
            ? 'Вы действительно хотите обновить это слово в облачной базе?'
            : 'Вы действительно хотите добавить это слово в облачную базе?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isSavingToCloud = true);

    try {
      final payloadWord = Map<String, dynamic>.from(wordData);
      if (isNoun && pluralCtrl.text.trim().isNotEmpty) {
        payloadWord["arabic"] =
            "${arabicCtrl.text.trim()} - ${pluralCtrl.text.trim()}";
      } else if (!isNoun && presentCtrl.text.trim().isNotEmpty) {
        payloadWord["arabic"] =
            "${pastCtrl.text.trim()} / ${presentCtrl.text.trim()}";
      }

      final payload = {"action": isEdit ? "edit" : "add", "word": payloadWord};

      try {
        await http
            .post(Uri.parse(MainScreenState._appsScriptUrl.trim()),
                headers: {"Content-Type": "application/json"},
                body: json.encode(payload))
            .timeout(const Duration(seconds: 15));
      } catch (networkError) {
        // На вебе/Safari ClientException часто срабатывает из-за CORS уже после успешного сохранения в таблице
        print('Web network notice: $networkError');
      }

      // АВТОМАТИЧЕСКАЯ СИНХРОНИЗАЦИЯ БАЗЫ ПОСЛЕ ОТПРАВКИ
      await MainScreen.instance.syncCloudData(showFeedback: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Успешно сохранено и база обновлена!'),
            backgroundColor: AppColors.primaryGreen));
        Navigator.pop(context, {'action': 'save', 'word': wordData});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => isSavingToCloud = false);
    }
  }

  Future<void> _deleteFromCloud() async {
    final wordData = widget.existingWord;
    if (wordData == null ||
        wordData['id'] == null ||
        wordData['id'].toString().isEmpty) {
      Navigator.pop(context, {'action': 'delete'});
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление'),
        content:
            const Text('Удалить это слово из облака и обновить базу?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isSavingToCloud = true);

    try {
      final payload = {
        "action": "delete",
        "word": {"id": wordData['id']}
      };

      try {
        await http
            .post(Uri.parse(MainScreenState._appsScriptUrl.trim()),
                headers: {"Content-Type": "application/json"},
                body: json.encode(payload))
            .timeout(const Duration(seconds: 15));
      } catch (networkError) {
        print('Web network notice: $networkError');
      }

      // АВТОМАТИЧЕСКАЯ СИНХРОНИЗАЦИЯ БАЗЫ ПОСЛЕ УДАЛЕНИЯ
      await MainScreen.instance.syncCloudData(showFeedback: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Слово удалено, база актуализирована!'),
            backgroundColor: AppColors.primaryGreen));
        Navigator.pop(context, {'action': 'delete', 'word': wordData});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Ошибка удаления: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => isSavingToCloud = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxVolume = max(4, volume);
    final maxPart = max(2, part);
    final maxChapter = max(30, chapter);

    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(widget.existingWord == null ? 'Новое слово' : 'Редактировать'),
          if (widget.isAdmin &&
              widget.existingWord != null &&
              widget.existingWord!['id'] != null)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              tooltip: 'Удалить из облака',
              onPressed: isSavingToCloud ? null : _deleteFromCloud,
            )
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                              labelText: 'Том',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8)),
                          value: volume,
                          isExpanded: true,
                          items: List.generate(maxVolume, (i) => i + 1)
                              .map((i) =>
                                  DropdownMenuItem(value: i, child: Text('$i')))
                              .toList(),
                          onChanged: (v) => setState(() => volume = v!))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                              labelText: 'Часть',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8)),
                          value: part,
                          isExpanded: true,
                          items: List.generate(maxPart, (i) => i + 1)
                              .map((i) =>
                                  DropdownMenuItem(value: i, child: Text('$i')))
                              .toList(),
                          onChanged: (v) => setState(() => part = v!))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                              labelText: 'Глава',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8)),
                          value: chapter,
                          isExpanded: true,
                          items: List.generate(maxChapter, (i) => i + 1)
                              .map((i) =>
                                  DropdownMenuItem(value: i, child: Text('$i')))
                              .toList(),
                          onChanged: (v) => setState(() => chapter = v!))),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: 'Текст / Диалог',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                value: selectedTextTitle,
                isExpanded: true,
                items: _dropdownTitles.map((String title) {
                  return DropdownMenuItem<String>(
                    value: title,
                    child: Text(title.isEmpty ? 'Не выбрано' : title,
                        overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedTextTitle = newValue;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Глагол',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Switch(
                      value: isNoun,
                      activeColor: AppColors.primaryGreen,
                      onChanged: (val) => setState(() => isNoun = val)),
                  const Text('Сущест.',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: arabicCtrl,
                  style: GoogleFonts.notoNaskhArabic(
                      fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                  decoration: InputDecoration(
                      labelText:
                          isNoun ? 'Ед. число (арабское)*' : 'Арабское слово*',
                      border: const OutlineInputBorder()),
                  textDirection: TextDirection.rtl,
                  validator: (v) => v!.isEmpty ? 'Заполните поле' : null),
              const SizedBox(height: 12),
              if (isNoun)
                TextFormField(
                    controller: pluralCtrl,
                    style: GoogleFonts.notoNaskhArabic(
                        fontSize: 22, height: 1.4),
                    decoration: const InputDecoration(
                        labelText: 'Мн. число (арабское)',
                        border: OutlineInputBorder()),
                    textDirection: TextDirection.rtl)
              else
                Row(
                  children: [
                    Expanded(
                        child: TextFormField(
                            controller: pastCtrl,
                            style: GoogleFonts.notoNaskhArabic(
                                fontSize: 22, height: 1.4),
                            decoration: const InputDecoration(
                                labelText: 'Прошедшее',
                                border: OutlineInputBorder()),
                            textDirection: TextDirection.rtl,
                            validator: (v) =>
                                v!.isEmpty ? 'Заполните' : null)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                            controller: presentCtrl,
                            style: GoogleFonts.notoNaskhArabic(
                                fontSize: 22, height: 1.4),
                            decoration: const InputDecoration(
                                labelText: 'Настоящее',
                                border: OutlineInputBorder()),
                            textDirection: TextDirection.rtl,
                            validator: (v) =>
                                v!.isEmpty ? 'Заполните' : null)),
                  ],
                ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: translationCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Перевод (русский)*',
                      border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? 'Заполните поле' : null),
              const SizedBox(height: 24),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Дополнительные поля',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen)),
              ),
              if (!isNoun) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: AutocompleteTextField(
                        controller: masdarCtrl,
                        options: _arabicWordOptions,
                        label: 'Масдар (ar)',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                          controller: masdarRuCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Масдар (ru)',
                              border: OutlineInputBorder())),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: AutocompleteTextField(
                      controller: synonymCtrl,
                      options: _arabicWordOptions,
                      label: 'Синоним 1 (ar)',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AutocompleteTextField(
                      controller: synonym2Ctrl,
                      options: _arabicWordOptions,
                      label: 'Синоним 2 (ar)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: AutocompleteTextField(
                      controller: antonymCtrl,
                      options: _arabicWordOptions,
                      label: 'Антоним (ar)',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                        controller: antonymRuCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Антоним (ru)',
                            border: OutlineInputBorder())),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: exampleArCtrl,
                  style: GoogleFonts.notoNaskhArabic(fontSize: 18, height: 1.4),
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Пример (арабский)',
                      border: OutlineInputBorder()),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 12),
              TextFormField(
                  controller: exampleRuCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Пример (русский)',
                      border: OutlineInputBorder())),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
        FilledButton(
            onPressed: isSavingToCloud ? null : _saveLocal,
            style: FilledButton.styleFrom(
                backgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.black87),
            child: const Text('Локально')),
        if (widget.isAdmin)
          FilledButton.icon(
              onPressed: isSavingToCloud ? null : _saveToCloud,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen),
              icon: isSavingToCloud
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: Text(isSavingToCloud ? 'Отправка...' : 'В Облако')),
      ],
    );
  }
}

class AutocompleteTextField extends StatelessWidget {
  final TextEditingController controller;
  final List<String> options;
  final String label;

  const AutocompleteTextField({
    super.key,
    required this.controller,
    required this.options,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        return options.where((String option) {
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        if (textEditingController.text != controller.text &&
            controller.text.isNotEmpty) {
          textEditingController.text = controller.text;
        }
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          style: GoogleFonts.notoNaskhArabic(fontSize: 18, height: 1.4),
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          textDirection: TextDirection.rtl,
          onChanged: (val) {
            controller.text = val;
          },
        );
      },
    );
  }
}

class WordDetailScreen extends StatelessWidget {
  final dynamic wordData;

  const WordDetailScreen({super.key, required this.wordData});

  Widget _buildInfoCard(String title, String? ar, String? ru) {
    if ((ar == null || ar.isEmpty) && (ru == null || ru.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (ar != null && ar.isNotEmpty)
            Text(ar,
                style: GoogleFonts.notoNaskhArabic(
                    fontSize: 24, color: AppColors.textDark, height: 1.4),
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl),
          if (ru != null && ru.isNotEmpty)
            Text(ru,
                style:
                    const TextStyle(fontSize: 16, color: AppColors.textGrey),
                textAlign: TextAlign.right),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayArabic = MainScreenState.formatArabicWord(wordData);
    final String synonyms = [wordData['synonym'], wordData['synonym_2']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join(' ، ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали слова'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.lightGreenCard,
                        child: IconButton(
                          icon: const Icon(Icons.volume_up,
                              color: AppColors.primaryGreen),
                          onPressed: () =>
                              MainScreenState.speak(wordData['arabic']),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          displayArabic,
                          style: GoogleFonts.notoNaskhArabic(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              height: 1.3),
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    wordData['translation'] ?? '',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textGrey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.lightGreenCard,
                  borderRadius: BorderRadius.circular(16)),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  Text('Том ${wordData['bookVolume'] ?? '-'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen)),
                  const Text('•',
                      style: TextStyle(color: AppColors.primaryGreen)),
                  Text('Часть ${wordData['bookPart'] ?? '-'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen)),
                  const Text('•',
                      style: TextStyle(color: AppColors.primaryGreen)),
                  Text('Глава ${wordData['chapter'] ?? '-'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen)),
                ],
              ),
            ),
            if (wordData['text_title'] != null &&
                wordData['text_title'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  wordData['text_title'],
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textGrey,
                      fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            const Text('Атрибуты',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 12),
            _buildInfoCard('Масдар', wordData['masdar'], wordData['masdar_ru']),
            _buildInfoCard('Синонимы', synonyms, null),
            _buildInfoCard(
                'Антоним', wordData['antonym'], wordData['antonym_ru']),
            if (wordData['example_arabic'] != null &&
                wordData['example_arabic'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Пример в контексте',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: AppColors.lightBeigeCard,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(wordData['example_arabic'],
                        style: GoogleFonts.notoNaskhArabic(
                            fontSize: 24,
                            color: AppColors.textDark,
                            height: 1.4),
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right),
                    const SizedBox(height: 8),
                    if (wordData['example_russian'] != null &&
                        wordData['example_russian'].toString().isNotEmpty)
                      Text(wordData['example_russian'],
                          style: const TextStyle(
                              fontSize: 16, color: AppColors.textGrey),
                          textAlign: TextAlign.right),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}