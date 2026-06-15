namespace Domain.Models.MinIO
{ 
    public class MinIOConfig
    {
        public string Endpoint { get; set; } = string.Empty;
        public string ExternalEndpoint { get; set; }
        public string PublicEndpoint { get; set; }
        public string AccessKey { get; set; } = string.Empty;
        public string SecretKey { get; set; } = string.Empty;
        public string BucketName { get; set; } = string.Empty;
        public bool UseSSL { get; set; } = false;
    }
}
