import 'package:flutter/material.dart';

class ContentBlock {
  final String type; // 'dialog' или 'story'
  final String contentId; // Уникальный идентификатор блока
  final Map<String, dynamic> data; // Данные для диалога или истории

  ContentBlock({
    required this.type,
    required this.contentId,
    required this.data,
  });

  // Метод для получения текста на арабском языке
  String get arabicText => data['text_ar'] ?? '';

  // Метод для получения текста на русском языке
  String get russianText => data['text_ru'] ?? '';

  // Метод для получения списка реплик (если тип диалог)
  List<Map<String, String>> get replies => data['replies'] as List<Map<String, String>> ?? [];
}