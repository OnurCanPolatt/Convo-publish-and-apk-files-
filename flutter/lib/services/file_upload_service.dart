import 'dart:io';
import 'dart:convert';
import 'dart:typed_data'; // 🚨 Düzeltme 1: Uint8List için bu import şart
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/chunk_upload_model.dart'; // Model yolun

class FileUploadService {
  final String baseUrl;
  final String token;

  FileUploadService({required this.baseUrl, required this.token});

  // 'onProgress' isminde bir geri bildirim parametresi ekledik
  Future<String?> uploadFile(File file, {Function(double)? onProgress}) async {
    final String fileName = p.basename(file.path);
    final int fileSize = await file.length();
    final String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    const int chunkSize = 1024 * 1024; // 1MB
    final int totalChunks = (fileSize / chunkSize).ceil();

    final Uint8List fileBytes = await file.readAsBytes();

    for (int i = 0; i < totalChunks; i++) {
      int start = i * chunkSize;
      int end = (start + chunkSize > fileSize) ? fileSize : start + chunkSize;
      List<int> chunk = fileBytes.sublist(start, end);

      final model = ChunkUploadModel(
        fileName: fileName,
        chunkIndex: i,
        chunkSize: chunk.length,
        sessionId: sessionId,
        totalChunks: totalChunks,
      );

      bool success = await _sendChunk(chunk, model);
      if (!success) return null;

      // 🚨 Yüzde hesaplama ve UI'ya bildirme
      if (onProgress != null) {
        double percent = (i + 1) / totalChunks;
        onProgress(percent); // Ekrana yeni yüzdeyi gönder
      }
    }

    return await _completeUpload(sessionId, fileName);
  }

  Future<bool> _sendChunk(List<int> chunkData, ChunkUploadModel model) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/Download/chunk"),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(model.toMap());

      var multipartFile = http.MultipartFile.fromBytes(
        'Chunk',
        chunkData,
        filename: model.fileName,
      );
      request.files.add(multipartFile);

      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _completeUpload(String sessionId, String fileName) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/Download/complete"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"SessionId": sessionId, "FileName": fileName}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Backend yapına göre MinIOResult içindeki DownloadUrl'i alıyoruz
        return data['minIOResult']['downloadUrl'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
