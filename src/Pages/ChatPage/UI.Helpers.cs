using Microsoft.JSInterop;
using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Components.Forms;

namespace Convo.Shared.Pages.ChatPage
{
    partial class ChatPanel
    {
        #region UI Helpers
        
        // ✅ Null-safe profile image style
        private string GetProfileImageStyle(string? imageUrl)
        {
            if (string.IsNullOrEmpty(imageUrl) || imageUrl == "/images/default-avatar.png")
            {
                return "background-color: #E6E7ED;";
            }
            return $"background-image: url('{imageUrl}'); background-size: cover; background-position: center;";
        }

        // ✅ Safe scroll with null checks and disposed state check
        private async Task ScrollToBottom()
        {
            // 1. Güvenlik Kontrolü: Bileşen silinmişse veya JS henüz hazır değilse çık
            if (_disposed || _isDisposing || !_jsInitialized || JSRuntime == null)
                return;

            try
            {
                // 2. DOM'un güncellenmesi için bir nefes payı bırak (ÇOK ÖNEMLİ)
                await Task.Delay(50);

                string containerId = isInVideoCall ? "videoMessagesContainer" : "messagesContainer";
        
                // 3. JS çağrısını yap
                await JSRuntime.InvokeVoidAsync("scrollToBottom", containerId);
            }
            catch (Exception ex) when (ex is JSDisconnectedException || ex is ObjectDisposedException)
            {
                // Bağlantı koptuysa veya bileşen o sırada kapandıysa sessizce yut
            }
            catch (Exception ex)
            {
                // Diğer gerçek hataları logla
                Console.WriteLine($"⚠️ Scroll to bottom error: {ex.Message}");
            }
        }

        #endregion
    }
}