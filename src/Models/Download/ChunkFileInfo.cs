namespace Domain.Models.Download
{
    public class ChunkFileInfo
    {
        public int Index { get; set; }
        public string FileName { get; set; }
        public long Size { get; set; }
        public string SizeFormatted { get; set; }
        public bool IsCompleted { get; set; }
    }
}
