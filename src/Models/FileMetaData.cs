namespace Domain.Models
{
    public class FileMetadata
    {
        public string OriginalFileName { get; set; }
        public long FileSize { get; set; }
        public string ContentType { get; set; }
        public long ChunkSize { get; set; }
        public int TotalChunks { get; set; }
        public string DownloadFolder { get; set; }
        public List<ChunkInfo> Chunks { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}
