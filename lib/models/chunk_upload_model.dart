class ChunkUploadModel {
  final String fileName;
  final int chunkIndex;
  final int chunkSize;
  final String sessionId;
  final int totalChunks;

  ChunkUploadModel({
    required this.fileName,
    required this.chunkIndex,
    required this.chunkSize,
    required this.sessionId,
    required this.totalChunks,
  });

  // Bu metot, veriyi sunucuya gönderirken Map (JSON benzeri) formatına çevirmemizi sağlar.
  Map<String, String> toMap() {
    return {
      'fileName': fileName,
      'chunkIndex': chunkIndex.toString(),
      'chunkSize': chunkSize.toString(),
      'sessionId': sessionId,
      'totalChunks': totalChunks.toString(),
    };
  }
}
