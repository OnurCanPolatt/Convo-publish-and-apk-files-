using Domain.Models.MinIO;
namespace Domain.Models.Download
{
    public class DownloadResult
    {
        public bool Success { get; set; }
        public string ErrorMessage { get; set; }
        public string FileName { get; set; }
        public long FileSize { get; set; }
        public string FileId { get; set; }
        public string FileSizeFormatted { get; set; }
        public string ContentType { get; set; }
        public string DownloadFolder { get; set; }
        public long ChunkSize { get; set; }
        public string ChunkSizeFormatted { get; set; }
        public long TotalChunks { get; set; }
        public int ProcessedChunks { get; set; }
        public List<ChunkFileInfo> ChunkFiles { get; set; }
        public DateTime ProcessedAt { get; set; }
        public MinIOUploadResult? MinIOResult { get; set; } // YENİ

    }
}
