using Convo.Shared.Wrappers;
using Domain.Entities;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.JSInterop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Interfaces;
using Microsoft.Extensions.DependencyInjection;

namespace Convo.Shared.Pages.GroupChatPage
{
    partial class GroupChatPanel
    {
        // ✅ EKLEME: Pending mesaj bilgileri
        private Guid _pendingFileMessageId;
        private DateTime _pendingFileMessageTime;

        #region File Upload UI Methods

        private async Task HandleFileSelected(InputFileChangeEventArgs e)
        {
            selectedFile = e.File;

            if (selectedFile != null)
            {
                if (selectedFile.Size > 100 * 1024 * 1024)
                {
                    await JSRuntime.InvokeVoidAsync("showErrorDialog",
                        "Dosya Çok Büyük!",
                        "Dosya boyutu 100MB'dan büyük olamaz.");
                    selectedFile = null;
                    return;
                }

                // ✅ CRITICAL: Dosya seçildiği anda zaman ve ID oluştur
                _pendingFileMessageId = Guid.NewGuid();
                _pendingFileMessageTime = DateTime.UtcNow;
                
                Console.WriteLine($"📎 Grup dosyası seçildi: {selectedFile.Name}, MessageId: {_pendingFileMessageId}, Time: {_pendingFileMessageTime:o}");

                await InvokeAsync(StateHasChanged);
            }
        }

        private async Task SendSelectedFile()
        {
            if (selectedFile == null) return;
            
            try
            {
                isUploading = true;
                hasUploadError = false;
                uploadProgress = 0;
                uploadStatus = "Başlatılıyor...";
                await InvokeAsync(StateHasChanged);

                var fileWrapper = new BrowserFileWrapper(selectedFile);
        
                // Dosyayı upload et
                var result = await _downloadService.UploadFileAsync(fileWrapper, Guid.Empty.ToString(), myId);
        
                if (result.Success)
                {
                    // ✅ CRITICAL: Zamanı ve ID'yi ÖNCEKİ değerlerle değiştir
                    result.Message.Id = _pendingFileMessageId;
                    result.Message.SentAt = _pendingFileMessageTime;
                    result.Message.ChatRoomId = GroupId;
                    result.Message.ReceiverId = null;

                    Console.WriteLine($"✅ Grup dosyası yüklendi, zaman güncellendi: {result.Message.Id}, SentAt: {result.Message.SentAt:o}");

                    // UI ve cache'e ekle
                    AddMessageSafely(result.Message);
                    await InvokeAsync(StateHasChanged);
                    await Task.Delay(100);
                    await ScrollToBottom();

                    // SignalR ile gönder - ÖNCEKİ zaman ile
                    await JSRuntime.InvokeVoidAsync("window.signalRManager.sendMessage",
                        GroupId,
                        result.Message.Content,
                        result.Message.FileUrl,
                        result.Message.Type.ToString(),
                        result.Message.FileData.FileSize,
                        true, // isGroupMessage
                        result.Message.Id.ToString(),
                        result.Message.SentAt.ToString("o") // ✅ sentAt - ÖNCEKİ ZAMAN
                    );

                    Console.WriteLine($"✅ [GROUP FILE] SignalR'a grup dosya mesajı gönderildi: {result.Message.Id}, SentAt: {result.Message.SentAt:o}");

                    // Arka planda DB'ye kaydet
                    _ = Task.Run(async () =>
                    {
                        using var scope = ScopeFactory.CreateScope();
                        var messageService = scope.ServiceProvider.GetRequiredService<IMessageService>();
                        var cacheService = scope.ServiceProvider.GetRequiredService<ICacheService>();

                        await messageService.SaveMessage(result.Message);
                        await cacheService.AddGroupMessageToCacheAsync(result.Message, GroupId);
                    
                        Console.WriteLine($"✅ Grup dosya mesajı arka planda kaydedildi: {result.Message.Id}");
                    });

                    uploadStatus = "Gönderildi!";
                    selectedFile = null;
                    isUploading = false;
                }
            }
            catch (OperationCanceledException)
            {
                uploadStatus = "İptal edildi";
            }
            catch (Exception ex)
            {
                await JSRuntime.InvokeVoidAsync("showErrorDialog", "Upload Hatası", ex.Message);
                uploadStatus = "Başarısız";
                hasUploadError = true;
                uploadErrorMessage = ex.Message;
            }
            
            await InvokeAsync(StateHasChanged);
        }

        private async Task CancelUpload()
        {
            await _downloadService.CancelUploadAsync();
            await InvokeAsync(StateHasChanged);
        }

        private async Task RetryUpload()
        {
            if (selectedFile != null)
            {
                var fileWrapper = new BrowserFileWrapper(selectedFile);
                await _downloadService.RetryUploadAsync(fileWrapper, GroupId.ToString(), myId);
                await InvokeAsync(StateHasChanged);
            }
        }

        private async Task CancelFileSelection()
        {
            selectedFile = null;
            isUploading = false;
            uploadProgress = 0;
            uploadStatus = "";
            hasUploadError = false;
            uploadErrorMessage = "";
            await InvokeAsync(StateHasChanged);
        }
        
        #endregion
    }
}