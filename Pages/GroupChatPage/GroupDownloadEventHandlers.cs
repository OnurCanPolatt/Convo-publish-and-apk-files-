using Domain.Models.Download;
using Microsoft.AspNetCore.Components.Web;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.GroupChatPage
{
    public partial class GroupChatPanel
    {
        #region DownloadService Event Handlers

        private void OnUploadProgressChanged(UploadProgressEventArgs args)
        {
            if(args != null)
            {
                uploadProgress = args.ProgressPercentage;
                uploadSpeed = args.Speed ?? uploadSpeed;
                remainingTime = args.RemainingTime ?? remainingTime;

                // InvokeAsync ile UI thread'e yönlendir
                _ = InvokeAsync(StateHasChanged);
            }
        }


        private void OnUploadStatusChanged(string status)
        {
            uploadStatus = status;
            InvokeAsync(StateHasChanged);
        }

        private void OnUploadError(string errorMessage)
        {
            hasUploadError = !string.IsNullOrEmpty(errorMessage);
            uploadErrorMessage = errorMessage;
            InvokeAsync(StateHasChanged);
        }

        private void OnUploadCompleted()
        {
            isUploading = false;
            selectedFile = null;
            uploadProgress = 100;
            InvokeAsync(StateHasChanged);
        }

        private void OnUploadCancelled()
        {
            isUploading = false;
            selectedFile = null;
            uploadProgress = 0;
            uploadStatus = "İptal edildi";
            InvokeAsync(StateHasChanged);
        }
        private async Task HandleKeyPress(KeyboardEventArgs e)
        {
            if (e.Key == "Enter" && !e.ShiftKey)
            {
                await SendTextMessage();
            }
        }

        #endregion

    }
}
