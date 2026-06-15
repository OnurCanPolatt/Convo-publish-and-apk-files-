// lib/widgets/fullscreen_image_page.dart (Yeni bir dosya oluşturabilirsin)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class FullscreenImagePage extends StatelessWidget {
  final String imageUrl;
  final String tag; // Hero animasyonu için benzersiz bir etiket

  const FullscreenImagePage({
    super.key,
    required this.imageUrl,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: tag,
              child: InteractiveViewer(
                // Zoom yapabilmeyi sağlar
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
