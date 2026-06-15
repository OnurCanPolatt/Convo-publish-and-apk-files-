using Domain.Models.Download;
using Microsoft.AspNetCore.Components.Web;
using System;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ChatPage
{
    public partial class ChatPanel
    {
        #region DownloadService Event Handlers

        // ✅ Safe event handler with null checks
        private void OnUploadProgressChanged(UploadProgressEventArgs? args)
        {
            if (_disposed || args == null)
                return;

            try
            {
                uploadProgress = args.ProgressPercentage;
                
                if (!string.IsNullOrEmpty(args.Speed))
                    uploadSpeed = args.Speed;
                    
                if (!string.IsNullOrEmpty(args.RemainingTime))
                    remainingTime = args.RemainingTime;

                InvokeAsync(StateHasChanged);

            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ OnUploadProgressChanged error: {ex.Message}");
            }
        }

        // ✅ Safe event handler
        private void OnUploadStatusChanged(string? status)
        {
            if (_disposed)
                return;

            try
            {
                uploadStatus = status ?? "";
                InvokeAsync(StateHasChanged);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ OnUploadStatusChanged error: {ex.Message}");
            }
        }

        // ✅ Safe event handler
        private void OnUploadError(string? errorMessage)
        {
            if (_disposed)
                return;

            try
            {
                hasUploadError = !string.IsNullOrEmpty(errorMessage);
                uploadErrorMessage = errorMessage ?? "";
                InvokeAsync(StateHasChanged);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ OnUploadError error: {ex.Message}");
            }
        }

        // ✅ Safe event handler
        private void OnUploadCompleted()
        {
            if (_disposed)
                return;

            try
            {
                isUploading = false;
                selectedFile = null;
                uploadProgress = 100;
                InvokeAsync(StateHasChanged);

            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ OnUploadCompleted error: {ex.Message}");
            }
        }

        // ✅ Safe event handler
        private void OnUploadCancelled()
        {
            if (_disposed)
                return;

            try
            {
                isUploading = false;
                selectedFile = null;
                uploadProgress = 0;
                uploadStatus = "İptal edildi";
                InvokeAsync(StateHasChanged);

            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ OnUploadCancelled error: {ex.Message}");
            }
        }

        // ✅ Safe keyboard event handler
        private async Task HandleKeyPress(KeyboardEventArgs? e)
        {
            if (_disposed || e == null)
                return;

            try
            {
                if (e.Key == "Enter" && !e.ShiftKey)
                {
                    await SendTextMessage();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ HandleKeyPress error: {ex.Message}");
            }
        }

        #endregion
    }
}