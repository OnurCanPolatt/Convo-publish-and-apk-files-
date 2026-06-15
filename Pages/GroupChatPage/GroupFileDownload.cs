using Microsoft.JSInterop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.GroupChatPage
{
    public partial class GroupChatPanel
    {
        #region File Download
        private async Task DownloadFile(string filePath, string fileName)
        {
            try
            {
                fileName = string.IsNullOrWhiteSpace(fileName) ? "indirilen_dosya" : fileName;
                var downloadUrl = $"/api/Download/download?filePath={Uri.EscapeDataString(filePath)}";
                Console.WriteLine($"📥 Downloading file: {downloadUrl}");
                await JSRuntime.InvokeVoidAsync("downloadFileFromUrl", downloadUrl, fileName);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Download error: {ex.Message}");
                await JSRuntime.InvokeVoidAsync("showErrorDialog", "İndirme Hatası", $"Dosya indirilemedi: {ex.Message}");
            }
        }
        #endregion

    }
}
