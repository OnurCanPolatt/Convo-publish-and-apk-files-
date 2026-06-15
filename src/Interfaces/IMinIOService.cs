using Domain.Models;
using Domain.Models.MinIO;
using Domain.Models.Download;
namespace Domain.Interfaces
{
    public interface IMinIOService
    {
        Task<string> GetDownloadUrlAsync(string objectName);

        /// <summary>
        /// Chunk dosyalarını MinIO'ya yükler ve compose ile birleştirir
        /// </summary>
        Task<MinIOUploadResult> UploadChunksAsync(string fileName, List<ChunkInfo> chunks, string downloadFolder);
        Task<MinIOUploadResult> UploadChunksParallelAsync(string fileName, List<ChunkInfo> chunks, string downloadFolder);

        /// <summary>
        /// MinIO'dan dosya indirir
        /// </summary>
        Task<Stream> DownloadFileAsync(string fileName);

        /// <summary>
        /// MinIO'daki dosyayı siler
        /// </summary>
        Task<bool> DeleteFileAsync(string fileName);

        /// <summary>
        /// MinIO'da dosya var mı kontrol eder
        /// </summary>
        Task<bool> FileExistsAsync(string fileName);

        /// <summary>
        /// MinIO'daki temp chunk'ları temizler
        /// </summary>
        Task<bool> CleanupTempChunksAsync(string fileName);
        Task<MinIOUploadResult> UploadFileAsync(Stream data, long size, string fileName, string contentType);
    }
}
