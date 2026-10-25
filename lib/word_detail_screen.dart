import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // Обязательный импорт для доступа к MainScreenState

class WordDetailScreen extends StatelessWidget {
  final Map<String, dynamic> wordData;

  const WordDetailScreen({super.key, required this.wordData});

  @override
  Widget build(BuildContext context) {
    // Получаем правильное отображение слова (прошедшее/настоящее время или ед./мн. число)
    final String formattedArabic = MainScreenState.formatArabicWord(wordData);
    final String translation = (wordData['translation'] ?? '').toString();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Детали слова', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. Главная карточка слова
          Card(
            elevation: 4,
            shadowColor: Colors.teal.withOpacity(0.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          formattedArabic,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.amiri(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade800,
                            height: 1.4,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 60,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.teal.shade100,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    translation,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Кнопка озвучки основного слова
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 32, color: Colors.teal),
                    onPressed: () => MainScreenState.speak(wordData['arabic'] ?? ''),
                    tooltip: 'Прослушать',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),

          // 2. Карточка дополнительных параметров (Масдар, Синонимы, Антонимы, Тексты)
          if (_hasValue(wordData['masdar']) || 
              _hasValue(wordData['masdar_ru']) || 
              _hasValue(wordData['synonym']) || 
              _hasValue(wordData['synonym_2']) ||
              _hasValue(wordData['antonym']) ||
              _hasValue(wordData['antonym_ru']) ||
              _hasValue(wordData['dialog_title']) ||
              _hasValue(wordData['text_title']))
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.teal.shade600),
                        const SizedBox(width: 8),
                        const Text('Дополнительно', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    const Divider(height: 24),
                    
                    if (_hasValue(wordData['masdar']))
                      _buildInfoRow('Масдар:', wordData['masdar'], isArabic: true),
                    
                    if (_hasValue(wordData['masdar_ru']))
                      _buildInfoRow('Перевод масдара:', wordData['masdar_ru'], isArabic: false),
                      
                    if (_hasValue(wordData['synonym']))
                      _buildInfoRow('Синоним 1:', wordData['synonym'], isArabic: true),
                    
                    if (_hasValue(wordData['synonym_2']))
                      _buildInfoRow('Синоним 2:', wordData['synonym_2'], isArabic: true),
                      
                    if (_hasValue(wordData['antonym']))
                      _buildInfoRow('Антоним:', wordData['antonym'], isArabic: true),
                    
                    if (_hasValue(wordData['antonym_ru']))
                      _buildInfoRow('Перевод антонима:', wordData['antonym_ru'], isArabic: false),

                    if (_hasValue(wordData['dialog_title']))
                      _buildInfoRow('Из диалога:', wordData['dialog_title'], isArabic: false),
                    
                    if (_hasValue(wordData['text_title']) && !_hasValue(wordData['dialog_title']))
                      _buildInfoRow('Из текста:', wordData['text_title'], isArabic: false),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // 3. Карточка примера использования
          if (_hasValue(wordData['example_arabic']))
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.format_quote, color: Colors.orange.shade600),
                        const SizedBox(width: 8),
                        // Expanded предотвращает ошибку "Right overflowed"
                        const Expanded(
                          child: Text(
                            'Пример использования', 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Озвучка примера
                        IconButton(
                          icon: const Icon(Icons.volume_up, size: 24, color: Colors.orange),
                          onPressed: () => MainScreenState.speak(wordData['example_arabic'] ?? ''),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        wordData['example_arabic'] ?? '',
                        style: GoogleFonts.amiri(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_hasValue(wordData['example_russian']))
                      Text(
                        wordData['example_russian'] ?? '',
                        style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasValue(dynamic val) {
    if (val == null) return false;
    return val.toString().trim().isNotEmpty;
  }

  Widget _buildInfoRow(String label, dynamic value, {bool isArabic = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120, // Ширина для русских подписей, чтобы не съезжали
            child: Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))
          ),
          Expanded(
            child: Text(
              value.toString(), 
              style: isArabic 
                  ? GoogleFonts.amiri(fontSize: 22, fontWeight: FontWeight.bold)
                  : const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              textAlign: isArabic ? TextAlign.right : TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}