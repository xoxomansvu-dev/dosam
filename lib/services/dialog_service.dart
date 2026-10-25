import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/dialog_content.dart'

class DialogService {
  static const String _baseUrl = 'YOUR_GOOGLE_SHEETS_ENDPOINT';

  static Future<List<DialogContent>> fetchDialogs() async {
    try {
      final response = await http.get(Uri.parse(_baseUrl + '/dialogs'),
          headers: {'Content-Type': 'application/json'});
      if (response.statusCode != 200) {
        throw Exception('Failed to load dialogs: ${response.statusCode}');
      }
      final jsonData = json.decode(response.body);
      return _parseDialogsFromJson(jsonData);
    } catch (e) {
      throw Exception('Error fetching dialogs: $e');
    }
  }

  static List<DialogContent> _parseDialogsFromJson(List<dynamic> jsonList) {
    return jsonList.map((jsonItem) {
      final blocks = _parseDialogBlocks(jsonItem['blocks']);
      return DialogContent(
        id: jsonItem['id'],
        title: jsonItem['title'],
        type: jsonItem['type'] ?? 'story',
        blocks: blocks,
      );
    }).toList();
  }

  static List<DialogBlock> _parseDialogBlocks(List<dynamic> jsonBlocks) {
    return jsonBlocks.map((jsonBlock) {
      final replies = jsonBlock['replies'] as List<Map<String, String>>?;
      final data = {
        'text_ar': jsonBlock['text_ar'],
        'text_ru': jsonBlock['text_ru'],
        'replies': replies,
        'speaker_ar': jsonBlock['speaker_ar'] ?? '',
        'speaker_ru': jsonBlock['speaker_ru'] ?? '',
      };
      return DialogBlock(
        contentId: jsonBlock['id'] ?? '',
        data: data,
      );
    }).toList();
  }
}