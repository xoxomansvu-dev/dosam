import 'package:flutter/material.dart';
import '../models/dialog_content.dart';
import '../services/dialog_service.dart';
import 'package:flutter_tts/flutter_tts.dart'
import 'package:flutter/material.dart';
import '../models/lesson_item.dart';
import '../models/content_block.dart';
import '../services/lesson_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

class DialogsAndStoriesScreen extends StatefulWidget {
  const DialogsAndStoriesScreen({super.key});

  @override
  State<DialogsAndStoriesScreen> createState() => _DialogsAndStoriesScreenState();
}

class _DialogsAndStoriesScreenState extends State<DialogsAndStoriesScreen> {
  final FlutterTTS _tts = FlutterTTS();
  List<LessonItem> lessons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      final lessonsData = await LessonService.fetchLessons();
      setState(() {
        this.lessons = lessonsData;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка загрузки уроков: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _speakText(String text) async {
    try {
      await _tts.setLanguage('en-US'); // Укажите нужный язык
      await _tts.speak(text);
    } catch (e) {
      print('Ошибка озвучки: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диалоги и истории'),
      ),
      body: ListView.builder(
        itemCount: lessons.length,
        itemBuilder: (context, index) {
          final lesson = lessons[index];
          return Card(
            child: ListTile(
              title: Text(lesson.title),
              subtitle: Text('Тип: ${lesson.type}'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _LessonDetailScreen(lesson: lesson),
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

class _LessonDetailScreen extends StatefulWidget {
  final LessonItem lesson;
  const _LessonDetailScreen({super.key, required this.lesson});

  @override
  State<_LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<_LessonDetailScreen> {
  final FlutterTTS _tts = FlutterTTS();
  final List<ContentBlock> _blocks = [];

  @override
  void initState() {
    super.initState();
    _blocks.addAll(widget.lesson.blocks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lesson.title),
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (widget.lesson.type == 'dialog') {
      return _buildDialog();
    } else {
      return _buildStory();
    }
  }

  Widget _buildDialog() {
    return ListView.builder(
      itemCount: _blocks.length,
      itemBuilder: (context, index) {
        final block = _blocks[index];
        return Column(
          children: [
            _buildSpeakerRow(block), // Виджет для отображения роли
            _buildTextBlock(block), // Виджет для текста
          ],
        );
      },
    );
  }

  Widget _buildSpeakerRow(ContentBlock block) {
    final replies = block.data['replies'] as List<Map<String, String>>;
    return Column(
      children: replies.map((reply) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                  padding: EdgeInsets.all(8),
                ),
                child: Text(reply['speaker_ar'] ?? '', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade200,
                    borderRadius: BorderRadius.circular(10),
                    padding: EdgeInsets.all(8),
                  ),
                  child: Column(
                    children: [
                      Text(reply['text_ar'] ?? '', style: TextStyle(fontSize: 16)),
                      Text(reply['text_ru'] ?? '', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextBlock(ContentBlock block) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Text(block.arabicText, style: TextStyle(fontSize: 16)),
          Text(block.russianText, style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildStory() {
    return ListView.builder(
      itemCount: _blocks.length,
      itemBuilder: (context, index) {
        final block = _blocks[index];
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text(block.arabicText, style: TextStyle(fontSize: 16)),
              Text(block.russianText, style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _speakText(block.arabicText),
                child: const Text('Озвучить'),
              ),
            ],
          ),
        );
      },
    );
  }
}