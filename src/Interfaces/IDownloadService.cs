using Domain.Entities;
using Domain.Models.Download;

namespace Domain.Interfaces
{
    public interface IDownloadService : IDisposable
    {
        // Events
        event Action<UploadProgressEventArgs> OnUploadProgressChanged;
        event Action<string> OnUploadStatusChanged;
        event Action<string> OnUploadError;
        event Action OnUploadCompleted;
        event Action OnUploadCancelled;

        // Properties
        bool IsPaused { get; }

        // Main Methods
        Task<FileUploadResult> UploadFileAsync(IFileInput file, string receiverUserId, Guid senderId);

        // Upload Controls
        void PauseUpload();
        void ResumeUpload();
        Task CancelUploadAsync();
        Task RetryUploadAsync(IFileInput file, string receiverUserId, Guid senderId);

        // Utility Methods
        string GetFileIcon(string fileName);
        string GetFileSize(long bytes);
        string GetFileExtension(string fileName);
    }
}
