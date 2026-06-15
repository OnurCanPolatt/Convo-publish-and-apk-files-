namespace Domain.Models
{ 
    public class ChunkInfo
    {
        public int Index { get; set; }
        public string FileName { get; set; }
        public string FilePath { get; set; }
        public long Size { get; set; }
        public long StartPosition { get; set; }
        public long EndPosition { get; set; }
        public bool IsCompleted { get; set; }
    }
}
