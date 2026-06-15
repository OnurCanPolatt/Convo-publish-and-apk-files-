using Domain.Enums;
using Domain.FileDataType;

namespace Domain.Interfaces
{
    public interface IFileDataService
    {
        // Ana işlem metodu - dosya türüne göre otomatik yönlendirme
        Task<FileData> ProcessFileAsync(Stream fileStream, string fileName, string contentType, long fileSize);

        // Türe özel işlem metodları
        Task<FileData> ProcessImageFileAsync(Stream fileStream, string fileName, string contentType, long fileSize);
        Task<FileData> ProcessVideoFileAsync(Stream fileStream, string fileName, string contentType, long fileSize);
        Task<FileData> ProcessAudioFileAsync(Stream fileStream, string fileName, string contentType, long fileSize);
        Task<FileData> ProcessDocumentFileAsync(Stream fileStream, string fileName, string contentType, long fileSize);

        // Dosya okuma metodları
        Task<byte[]> GetFileDataAsync(IFileData fileData);
        Task<Stream> GetFileStreamAsync(IFileData fileData);

        // Yardımcı metodlar
        bool IsSmallFile(long fileSize);
        string GenerateUniqueFileName(string originalFileName);
        Task<bool> DeleteFileAsync(IFileData fileData);

        // Dosya doğrulama
        bool ValidateFileType(string contentType);
        bool ValidateFileSize(long fileSize, string contentType);

        // UI Helper Methods (DownloadService'ten taşındı)
        string GetFileIcon(string fileName);
        string GetFileSize(long bytes);
        string GetFileExtension(string fileName);
        string GetMessageContentForFileType(MessageType fileType, string fileName);

        // Type checking helper metodları
        bool IsImageFile(string contentType);
        bool IsVideoFile(string contentType);
        bool IsAudioFile(string contentType);
        bool IsDocumentFile(string contentType);
    }
}