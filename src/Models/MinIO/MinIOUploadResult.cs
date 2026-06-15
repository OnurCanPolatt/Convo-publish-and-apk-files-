namespace Domain.Models.MinIO
{
    public class MinIOUploadResult
    {
        public bool Success { get; set; }
        public string? ErrorMessage { get; set; }
        public string? MinIOPath { get; set; }
        public string FileId { get; set; }
        public string OriginalFileName{ get; set; }
        public string? DownloadUrl { get; set; }
        public int UploadedChunks { get; set; }
        public long TotalSize { get; set; }
        public string? TotalSizeFormatted { get; set; }
        public DateTime UploadedAt { get; set; }
    }
}
