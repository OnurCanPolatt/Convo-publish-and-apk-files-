using Microsoft.JSInterop;
using System;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ChatPage
{
    public partial class ChatPanel
    {
        #region File Download
        
        private async Task DownloadFile(string? fileUrl, string? fileName)
        {
            if (_disposed || JSRuntime == null || string.IsNullOrEmpty(fileUrl) || string.IsNullOrEmpty(fileName))
                return;

            try
            {
                // ✅ DOĞRUSU BU: Zaten var olan MinIO URL'ini direkt kullan
                var downloadUrl = fileUrl; 
                Console.WriteLine($"📥 Downloading file directly from MinIO: {downloadUrl}");

                await JSRuntime.InvokeVoidAsync("downloadFileFromUrl", downloadUrl, fileName);
            }
            catch (JSDisconnectedException)
            {
                Console.WriteLine("⚠️ Browser disconnected during download");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Download error: {ex.Message}");
        
                try
                {
                    await JSRuntime.InvokeVoidAsync("showErrorDialog", 
                        "İndirme Hatası", 
                        $"Dosya indirilemedi: {ex.Message}");
                }
                catch { }
            }
        }
        
        #endregion
    }
}