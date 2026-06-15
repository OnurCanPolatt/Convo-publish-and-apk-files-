using Convo.Shared.Wrappers;
using Domain.Entities;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.JSInterop;
using System;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ChatPage
{
    partial class ChatPanel
    {
        // ✅ EKLEME: Pending mesaj bilgileri
        private Guid _pendingFileMessageId;
        private DateTime _pendingFileMessageTime;

        #region File Upload UI Methods

        private async Task HandleFileSelected(InputFileChangeEventArgs e)
        {
            if (_disposed || e?.File == null)
                return;

            selectedFile = e.File;

            if (selectedFile.Size > 10L * 1024 * 1024 * 1024)
            {
                try
                {
                    await JSRuntime.InvokeVoidAsync("showErrorDialog",
                        "Dosya Çok Büyük!",
                        "Dosya boyutu 10 GB'dan büyük olamaz.");
                }
                catch (JSDisconnectedException) { }
                catch (Exception ex)
                {
                    Console.WriteLine($"⚠️ Error dialog failed: {ex.Message}");
                }

                selectedFile = null;
                return;
            }

            // ✅ CRITICAL: Dosya seçildiği anda zaman ve ID oluştur
            _pendingFileMessageId = Guid.NewGuid();
            _pendingFileMessageTime = DateTime.UtcNow;
            
            Console.WriteLine($"📎 Dosya seçildi: {selectedFile.Name}, MessageId: {_pendingFileMessageId}, Time: {_pendingFileMessageTime:o}");

            InvokeAsync(StateHasChanged);
        }

        private async Task SendSelectedFile()
        {
            if (_disposed || selectedFile == null || _messageService == null)
                return;

            try
            {
                isUploading = true;
                hasUploadError = false;
                uploadProgress = 0;
                uploadStatus = "Başlatılıyor...";
                InvokeAsync(StateHasChanged);

                var fileWrapper = new BrowserFileWrapper(selectedFile);

                // 1️⃣ Dosyayı upload et ve public URL al
                var result = await _downloadService.UploadFileAsync(fileWrapper, UserId.ToString(), myId);

                if (_disposed || result == null || !result.Success || result.Message == null)
                    return;

                var message = result.Message;

                // ✅ CRITICAL: Zamanı ve ID'yi ÖNCEKİ değerlerle değiştir
                message.Id = _pendingFileMessageId;
                message.SentAt = _pendingFileMessageTime;

                Console.WriteLine($"✅ Dosya yüklendi, zaman güncellendi: {message.Id}, SentAt: {message.SentAt:o}");

                // 2️⃣ DB'ye kaydet
                await _messageService.SaveMessage(message);

                // 3️⃣ Cache'e ekle
                await _cacheService.AddMessageToCacheAsync(message, myId, UserId);

                // 4️⃣ Thread-safe UI güncelleme
                AddMessageSafely(message);
                await InvokeAsync(StateHasChanged);
                await Task.Delay(100);
                await ScrollToBottom();

                // 5️⃣ SignalR'a gönder - ÖNCEKİ zaman ile
                if (JSRuntime != null && myInfo != null && message.FileData != null)
                {
                    try
                    {
                        await JSRuntime.InvokeVoidAsync("window.signalRManager.sendMessage",
                            UserId,                      // targetId
                            message.Content ?? "",       // content
                            message.FileUrl ?? "",       // fileUrl
                            message.Type.ToString(),     // messageType
                            message.FileData.FileSize,   // filesize
                            false,                       // isGroupMessage
                            message.Id.ToString(),       // messageId
                            message.SentAt.ToString("o") // ✅ sentAt - ÖNCEKİ ZAMAN
                        );

                        Console.WriteLine($"✅ [FILE] SignalR'a dosya mesajı gönderildi: {message.Id}, SentAt: {message.SentAt:o}");
                    }
                    catch (JSDisconnectedException)
                    {
                        Console.WriteLine("⚠️ Browser disconnected during file send");
                    }
                }

                uploadStatus = "Gönderildi!";
                
                // ✅ Temizle
                selectedFile = null;
                isUploading = false;
            }
            catch (OperationCanceledException)
            {
                uploadStatus = "İptal edildi";
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Upload error: {ex.Message}");
                try
                {
                    if (JSRuntime != null)
                    {
                        await JSRuntime.InvokeVoidAsync("showErrorDialog", "Upload Hatası", ex.Message);
                    }
                }
                catch { }

                uploadStatus = "Başarısız";
                hasUploadError = true;
                uploadErrorMessage = ex.Message;
            }

            InvokeAsync(StateHasChanged);
        }

        private async Task CancelUpload()
        {
            if (_disposed || _downloadService == null)
                return;

            try
            {
                await _downloadService.CancelUploadAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ Cancel upload error: {ex.Message}");
            }
        }

        private async Task RetryUpload()
        {
            if (_disposed || selectedFile == null || _downloadService == null)
                return;

            try
            {
                var fileWrapper = new BrowserFileWrapper(selectedFile);
                await _downloadService.RetryUploadAsync(fileWrapper, UserId.ToString(), myId);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Retry upload error: {ex.Message}");
            }
        }

        private void CancelFileSelection()
        {
            if (_disposed)
                return;

            selectedFile = null;
            isUploading = false;
            uploadProgress = 0;
            uploadStatus = "";
            hasUploadError = false;
            uploadErrorMessage = "";
            InvokeAsync(StateHasChanged);
        }
        
        private string GetFileSizeString(long bytes)
        {
            string[] sizes = { "B", "KB", "MB", "GB" };
            double len = bytes;
            int order = 0;
            while (len >= 1024 && order < sizes.Length - 1)
            {
                order++;
                len = len / 1024;
            }
            return $"{len:0.##} {sizes[order]}";
        }

        #endregion
    }
}