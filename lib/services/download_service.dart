// lib/services/download_service.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class FileDownloadService {
  final Dio _dio = Dio();

  Future<String?> downloadFile(
    String url,
    String fileName, {
    Function(double)? onProgress,
  }) async {
    try {
      // 1. İzinleri zorla
      if (Platform.isAndroid) {
        await Permission.storage.request();
      }

      // 2. Klasör Yolunu Al
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final String savePath = "${directory!.path}/$fileName";

      // 3. İndir
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      return savePath;
    } catch (e) {
      debugPrint("İndirme Hatası: $e");
      return null;
    }
  }
}
