class DialogContent {
  final String id;
  final String title;
  final String type;
  final List<DialogBlock> blocks;

  DialogContent({
    required this.id,
    required this.title,
    required this.type,
    required this.blocks,
  });
}

class DialogBlock {
  final String contentId;
  final Map<String, dynamic> data;

  DialogBlock({
    required this.contentId,
    required this.data,
  });
}