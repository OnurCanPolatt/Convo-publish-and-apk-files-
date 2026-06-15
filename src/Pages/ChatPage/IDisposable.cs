using System;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ChatPage
{
    // IAsyncDisposable zaten burada tanımlı kalsın
    public partial class ChatPanel : IAsyncDisposable
    {
        public async ValueTask DisposeAsync()
        {
            // Eğer zaten imha edildiyse veya ediliyorsa tekrar çalıştırma
            if (_disposed)
                return;

            _isDisposing = true; // Diğer asenkron metodlara "dur" sinyali
            _disposed = true;

            try
            {
                Console.WriteLine($"🧹 {UserId} için ChatPanel imha süreci başladı...");

                // 1. EventShop Aboneliklerini KESİN olarak temizle
                // _subscribed kontrolüne bakmaksızın çıkarıyoruz (en güvenli yol)
                EventShop.OnReceiveMessage -= HandleReceiveMessage;
                EventShop.OnFriendJoinedConference -= HandleFriendJoined;
                EventShop.OnP2pConferenceEnded -= HandleP2pConferenceEnded;
                _subscribed = false;

                // 2. DownloadService Aboneliklerini temizle
                if (_downloadService != null)
                {
                    _downloadService.OnUploadProgressChanged -= OnUploadProgressChanged;
                    _downloadService.OnUploadStatusChanged -= OnUploadStatusChanged;
                    _downloadService.OnUploadError -= OnUploadError;
                    _downloadService.OnUploadCompleted -= OnUploadCompleted;
                    _downloadService.OnUploadCancelled -= OnUploadCancelled;
                }

                // 3. Navigasyon Handler'ı (LocationChanging) temizle
                // Sayfadan çıkarken bu handler'ı serbest bırakmazsan bellek sızıntısı yapar
                _locationChangingHandler?.Dispose();

                // 4. Eğer aktif video görüşmesi varsa sonlandır
                if (isInVideoCall)
                {
                    try
                    {
                        await EndCall();
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"⚠️ Dispose sırasında arama sonlandırılamadı: {ex.Message}");
                    }
                }

                // 5. Mesaj listesini temizle
                ClearMessagesSafely();

                Console.WriteLine($"✅ {UserId} için ChatPanel başarıyla dispose edildi.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Dispose sırasında kritik hata: {ex.Message}");
            }
        }
    }
}