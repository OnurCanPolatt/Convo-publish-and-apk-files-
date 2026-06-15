namespace Domain.Models.Download
{
    public class ResumeInfo
    {
        public bool Success { get; set; }
        public string ErrorMessage { get; set; }
        public string OriginalFileName { get; set; }
        public int TotalChunks { get; set; }
        public int CompletedChunks { get; set; }
        public int IncompletedChunks { get; set; }
        public double CompletionPercentage { get; set; }
        public string DownloadFolder { get; set; }
        public List<ChunkFileInfo> CompletedChunksList { get; set; }
        public List<ChunkFileInfo> IncompletedChunksList { get; set; }
        public DateTime CheckedAt { get; set; }
    }
}
