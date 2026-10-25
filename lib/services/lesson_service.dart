import 'package:flutter/material.dart';
import '../models/lesson_item.dart';
import '../models/content_block.dart';
import '../models/dialog_content.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LessonService {
  static const String _baseUrl = https://docs.google.com/spreadsheets/d/e/2PACX-1vQ-3H7rxxqgcIcpbsVY8GtIzcvv3_q1aZ5l08SG4DjHbPGPMaORLBQmXWlAhgRONZ1fNkrzPi_XAZD3/pub?gid=0&single=true&output=csv; // Замените на реальный эндпоинт

  // Функция для парсинга данных из Google Таблиц
  static Future<List<LessonItem>> fetchLessons() async {
    final response = await http.get(Uri.parse(_baseUrl + '/lessons'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load lessons: ${response.statusCode}');
    }
    final jsonData = json.decode(response.body);
    return _parseLessonsFromJson(jsonData);
  }

  // Парсинг данных в модели LessonItem
  static List<LessonItem> _parseLessonsFromJson(List<dynamic> jsonList) {
    return jsonList.map((jsonItem) {
      final blocks = _parseContentBlocks(jsonItem['blocks']);
      return LessonItem(
        id: jsonItem['id'],
        title: jsonItem['title'],
        type: jsonItem['type'] ?? 'story', // 'dialog' или 'story'
        blocks: blocks,
      );
    }).toList();
  }

  // Парсинг блоков в модели ContentBlock
  static List<ContentBlock> _parseContentBlocks(List<dynamic> jsonBlocks) {
    return jsonBlocks.map((jsonBlock) {
      final data = {
        'text_ar': jsonBlock['text_ar'],
        'text_ru': jsonBlock['text_ru'],
        'replies': jsonBlock['replies'] ?? [],
      };
      return ContentBlock(
        type: jsonBlock['type'] ?? 'story',
        contentId: jsonBlock['id'],
        data: data,
      );
    }).toList();
  }
}