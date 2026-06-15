import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/screens/reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _apiService = ApiService();
  bool _loading = false;
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController =
        VideoPlayerController.asset('assets/videos/login-bgg.mp4')
          ..initialize().then((_) {
            _videoController.setLooping(true);
            _videoController.play();
            setState(() {});
          });
  }

  @override
  void dispose() {
    _videoController.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await _apiService.forgotPassword(_emailCtl.text.trim());
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) =>
              ResetPasswordScreen(email: _emailCtl.text.trim()),
        ),
      );
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hata'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cardMaxWidth = mq.size.width * 0.86;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _videoController.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController.value.size.width,
                      height: _videoController.value.size.height,
                      child: VideoPlayer(_videoController),
                    ),
                  )
                : Container(color: Colors.black),
          ),
          Positioned.fill(child: Container(color: Colors.black.withAlpha(51))),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardMaxWidth),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(217),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(38),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 22,
                      ),
                      child: _buildForm(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Convo',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.indigo[600],
            ),
          ),
          const SizedBox(height: 6),
          Text('Şifre Sıfırlama', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(
            'Kayıtlı e-posta adresinize 6 haneli kod göndereceğiz.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'E-posta Adresi',
              hintText: 'ornek@mail.com',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'E-posta girin';
              if (!v.contains('@')) return 'Geçerli bir e-posta girin';
              return null;
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[400],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _loading ? null : _sendCode,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Kod Gönder'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Giriş Sayfasına Dön'),
          ),
        ],
      ),
    );
  }
}
