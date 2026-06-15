namespace Domain.Models.MinIO
{
    public class ImageResult
    {
        public bool IsSuccess { get; set; }
        public Guid UserOrGroupId { get; set; }
        public string? OriginalImagePath { get; set; }
        public string? ThumbnailImagePath { get; set; }
        public string? OriginalImageUrl { get; set; }
        public string? ThumbnailImageUrl { get; set; }
        public long FileSize { get; set; }
        public string? ErrorMessage { get; set; }
        public DateTime UploadedAt { get; set; }
    }
}