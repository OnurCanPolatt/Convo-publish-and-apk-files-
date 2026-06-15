import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/discovery_provider.dart';
import '../services/auth_provider.dart';
import '../widgets/user_card.dart';
import 'dart:async';
import '../services/signalr/signalr_service.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  _DiscoveryScreenState createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final signalr = context.read<SignalrService>();
      final provider = context.read<DiscoveryProvider>();

      final String token = auth.token ?? "";
      final String userId = auth.currentUser?.userId ?? "";

      provider.refreshList(token, userId);

      // 2. 🚀 Dinleyiciyi Provider üzerinden başlatıyoruz.
      // Sayfa kapansa bile Provider dinlemeye devam edecek.
      provider.listenToSignalR(signalr, token, userId);
    });

    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final auth = context.read<AuthProvider>();
      final provider = context.read<DiscoveryProvider>();

      if (auth.token != null &&
          auth.currentUser?.userId != null &&
          !provider.isLoading &&
          provider.hasMore) {
        debugPrint("🚀 Discovery: loadNextPage() tetiklendi!");
        provider.loadNextPage(auth.token!, auth.currentUser!.userId!);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    // 🚨 NOT: _signalrSubscription artık Provider'da olduğu için burada cancel etmiyoruz.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            decoration: const InputDecoration(
              hintText: "Kullanıcı Ara...",
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 600), () {
                final auth = context.read<AuthProvider>();
                context.read<DiscoveryProvider>().updateSearch(
                  value,
                  auth.token ?? "",
                  auth.currentUser?.userId ?? "",
                );
              });
            },
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final auth = context.read<AuthProvider>();
          await context.read<DiscoveryProvider>().refreshList(
            auth.token!,
            auth.currentUser!.userId!,
          );
        },
        child: Consumer<DiscoveryProvider>(
          builder: (context, provider, child) {
            if (provider.users.isEmpty && provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.users.isEmpty) {
              return const Center(child: Text("Kullanıcı bulunamadı."));
            }

            // ✅ GÜNCELLEME: LayoutBuilder kullanarak her ekranda aynı oranı koruyoruz
            return LayoutBuilder(
              builder: (context, constraints) {
                // Ekran ne kadar geniş olursa olsun, dikey oranı (Boy/En) 0.68'de sabitliyoruz.
                // Eğer kartlar hala taşıyorsa 0.65'e çekebilirsin.
                const double cardAspectRatio = 0.68;

                return GridView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, // Yan yana 2 kart
                    childAspectRatio:
                        cardAspectRatio, // Oran sabit, taşma olmaz
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: provider.users.length + (provider.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < provider.users.length) {
                      return UserCard(user: provider.users[index]);
                    } else {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
