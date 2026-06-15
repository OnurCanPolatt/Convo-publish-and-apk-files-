import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:my_first_flutterapp/services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  final _apiService = ApiService();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
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
    _codeCtl.dispose();
    _passwordCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await _apiService.resetPassword(
        email: widget.email,
        code: _codeCtl.text.trim(),
        newPassword: _passwordCtl.text,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Şifreniz başarıyla değiştirildi!'),
          backgroundColor: Colors.green,
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
          Text('Yeni Şifre Belirle', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(
            '${widget.email} adresine kod gönderildi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codeCtl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '6 Haneli Kod',
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
            ),
            validator: (v) =>
                (v == null || v.length != 6) ? '6 haneli kodu girin' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtl,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: 'Yeni Şifre',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Şifre girin';
              if (v.length < 6) return 'En az 6 karakter';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmCtl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Şifre Tekrar',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) =>
                v != _passwordCtl.text ? 'Şifreler eşleşmiyor' : null,
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
              onPressed: _loading ? null : _resetPassword,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Şifreyi Güncelle'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Geri Dön'),
          ),
        ],
      ),
    );
  }
}
