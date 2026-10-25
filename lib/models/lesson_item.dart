import 'package:flutter/material.dart';

class LessonItem {
  final String id;
  final String title;
  final String type; // 'dialog' или 'story'
  final List<ContentBlock> blocks;

  LessonItem({
    required this.id,
    required this.title,
    required this.type,
    required this.blocks,
  });
}