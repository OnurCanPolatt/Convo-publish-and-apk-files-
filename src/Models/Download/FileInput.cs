namespace Domain.Models.Download
{
    public class FileInput
    {
        public string FileName { get; set; } = string.Empty;
        public string ContentType { get; set; } = string.Empty;
        public long Size { get; set; }
        public Func<long, Stream> OpenStream { get; set; }
    }
}