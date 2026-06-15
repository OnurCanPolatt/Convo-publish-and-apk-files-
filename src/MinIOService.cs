using Domain.Interfaces;
using Domain.Models;
using Domain.Models.MinIO;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Minio;
using Minio.DataModel.Args;
using Minio.Exceptions;
using System.Text.Json; // JSON ayrıştırması için eklendi
using System;
using System.Collections.Generic;
using System.IO;    
using System.Linq;
using System.Threading.Tasks;

namespace Infrastructure.Services
{
    public class MinIOService : IMinIOService
    {
        private readonly IMinioClient _minioClient;
        private readonly MinIOConfig _config;
        private readonly ILogger<MinIOService> _logger;

        public MinIOService(IOptions<MinIOConfig> config, ILogger<MinIOService> logger, IMinioClient minioClient)
        {
            _config = config.Value;
            _logger = logger;
            _minioClient = minioClient;
        }

        // ❗ GÜNCELLEME: Kovayı oluşturan ve public yapan birleşik metot
        private async Task EnsureBucketExistsAndIsPublicAsync()
        {
            try
            {
                var bucketExistsArgs = new BucketExistsArgs()
                    .WithBucket(_config.BucketName);

                bool found = await _minioClient.BucketExistsAsync(bucketExistsArgs).ConfigureAwait(false);

                if (!found)
                {
                    try
                    {
                        var makeBucketArgs = new MakeBucketArgs()
                            .WithBucket(_config.BucketName);
                        await _minioClient.MakeBucketAsync(makeBucketArgs).ConfigureAwait(false);
                        _logger.LogInformation($"✅ Bucket oluşturuldu: {_config.BucketName}");
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "❌ BUCKET OLUŞTURULAMADI: {BucketName}", _config.BucketName);
                        throw new InvalidOperationException($"MinIO bucket oluşturulamadı: {ex.Message}", ex);
                    }
                }

                // Kova varsa veya yeni oluşturulduysa, politikasını ayarla
                await EnsureBucketPolicyIsPublicAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ EnsureBucketExistsAsync genel hatası: {Message}", ex.Message);
                // Hatanın detayını görmek için InnerException'ı da logla
                if (ex.InnerException != null)
                {
                    _logger.LogError(ex.InnerException, "Inner Exception Detayı:");
                }
                throw; // Hatanın yukarıya (Controller'a) fırlatılması önemli
            }
        }

        // ❗ GÜNCELLEME: Politika ayarını yönetir (Daha sağlam hale getirildi)
        private async Task EnsureBucketPolicyIsPublicAsync()
        {
            try
            {
                // Politika JSON'u: Herkesin "files/" prefix'i altındaki dosyaları okumasına izin ver
                // ❗ DÜZELTME: Bucket ARN'ı "files/*" değil, "/*" olmalı ki tüm dosyalar public olsun
                var policyJson = $@"{{
                    ""Version"": ""2012-10-17"",
                    ""Statement"": [
                        {{
                            ""Effect"": ""Allow"",
                            ""Principal"": {{ ""AWS"": [""*""] }},
                            ""Action"": [""s3:GetObject""],
                            ""Resource"": [""arn:aws:s3:::{_config.BucketName}/*""]
                        }}
                    ]
                }}";

                // Mevcut politikayı almayı dene
                string currentPolicy = "";
                try
                {
                    var getPolicyArgs = new GetPolicyArgs()
                        .WithBucket(_config.BucketName);
                    currentPolicy = await _minioClient.GetPolicyAsync(getPolicyArgs).ConfigureAwait(false);
                }
                catch (MinioException ex) when (ex.Message.Contains("policy does not exist"))
                {
                    _logger.LogWarning("Bucket policy bulunamadı, yeni politika ayarlanacak.");
                    currentPolicy = "{}"; // Boş bir JSON olarak ayarla
                }
                catch (Exception ex)
                {
                     _logger.LogError(ex, "❌ Mevcut bucket politikası alınamadı.");
                     // Eğer politika alınamıyorsa, yine de yenisini ayarlamayı dene
                     currentPolicy = "{}";
                }

                // JSON'ları karşılaştır
                if (string.IsNullOrWhiteSpace(currentPolicy)) currentPolicy = "{}";

                var desiredPolicyDoc = JsonDocument.Parse(policyJson);
                var currentPolicyDoc = JsonDocument.Parse(currentPolicy);

                // Eğer mevcut politika, istediğimiz politika değilse, ayarla
                if (currentPolicyDoc.RootElement.ToString() != desiredPolicyDoc.RootElement.ToString())
                {
                    _logger.LogWarning("Mevcut politika güncel değil. Yeni politika ayarlanıyor...");
                    var setPolicyArgs = new SetPolicyArgs()
                        .WithBucket(_config.BucketName)
                        .WithPolicy(policyJson);
                    await _minioClient.SetPolicyAsync(setPolicyArgs).ConfigureAwait(false);
                    _logger.LogInformation($"✅ Bucket politikası public olarak ayarlandı: {_config.BucketName}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ BUCKET POLİTİKASI AYARLANAMADI: {BucketName}", _config.BucketName);
                throw new InvalidOperationException($"MinIO bucket politikası ayarlanamadı: {ex.Message}", ex);
            }
        }


        // ❗ GÜNCELLEME: Controller'ın kullandığı metot
        public async Task<MinIOUploadResult> UploadFileAsync(Stream data, long size, string fileName, string contentType)
        {
            try
            {
                _logger.LogInformation($"MinIO'ya stream upload başlıyor: {fileName}");

                // 1. Bucket var mı/public mi kontrol et
                await EnsureBucketExistsAndIsPublicAsync();

                // 2. Benzersiz dosya adı oluştur
                string fileId = Guid.NewGuid().ToString("N")[..8];
                string nameWithoutExt = Path.GetFileNameWithoutExtension(fileName);
                string extension = Path.GetExtension(fileName);
                var finalObjectName = $"files/{nameWithoutExt}_{fileId}{extension}";

                // 3. Stream'i MinIO'ya yükle
                var putObjectArgs = new PutObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(finalObjectName)
                    .WithStreamData(data)
                    .WithObjectSize(size)
                    .WithContentType(contentType);

                await _minioClient.PutObjectAsync(putObjectArgs).ConfigureAwait(false);

                _logger.LogInformation($"Dosya başarıyla yüklendi: {finalObjectName} ({FormatBytes(size)})");

                // 4. Sonucu döndür
                return new MinIOUploadResult
                {
                    Success = true,
                    MinIOPath = finalObjectName,
                    FileId = fileId,
                    OriginalFileName = fileName,
                    DownloadUrl = GenerateDownloadUrl(finalObjectName), // ❗ Akıllı URL üretecek
                    TotalSize = size,
                    TotalSizeFormatted = FormatBytes(size),
                    UploadedAt = DateTime.Now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Genel stream upload hatası: {fileName}");
                return new MinIOUploadResult
                {
                    Success = false,
                    ErrorMessage = ex.Message
                };
            }
        }

        public async Task<MinIOUploadResult> UploadChunksAsync(string fileName, List<ChunkInfo> chunks, string downloadFolder)
        {
            try
            {
                _logger.LogInformation($"MinIO'ya dosya upload başlıyor: {fileName}");

                // 1. Bucket var mı kontrol et, yoksa oluştur
                await EnsureBucketExistsAndIsPublicAsync();

                // Benzersiz ID oluştur
                string fileId = Guid.NewGuid().ToString("N")[0..8]; // Kısa ID: abc123de

                // Dosya adı + ID birleştir
                string nameWithoutExt = Path.GetFileNameWithoutExtension(fileName);
                string extension = Path.GetExtension(fileName);
                var finalObjectName = $"files/{nameWithoutExt}_{fileId}{extension}";
                // 2. Chunk'ları birleştirip stream oluştur
                using var combinedStream = CreateCombinedStream(chunks);

                // 3. PutObjectAsync otomatik multipart yapacak (>5MB için)
                var putObjectArgs = new PutObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(finalObjectName)
                    .WithStreamData(combinedStream)
                    .WithObjectSize(combinedStream.Length)
                    .WithContentType("application/octet-stream");

                await _minioClient.PutObjectAsync(putObjectArgs).ConfigureAwait(false);

                var totalSize = chunks.Sum(c => c.Size);
                _logger.LogInformation($"Dosya başarıyla yüklendi: {finalObjectName} ({FormatBytes(totalSize)})");

                return new MinIOUploadResult
                {
                    Success = true,
                    MinIOPath = finalObjectName,
                    FileId = fileId,  // ID'yi ayrıca döndür
                    OriginalFileName = fileName,  // Orijinal dosya adı
                    DownloadUrl = GenerateDownloadUrl(finalObjectName),
                    UploadedChunks = chunks.Count,
                    TotalSize = totalSize,
                    TotalSizeFormatted = FormatBytes(totalSize),
                    UploadedAt = DateTime.Now
                };
            }
            catch (MinioException ex)
            {
                _logger.LogError(ex, $"MinIO upload hatası: {fileName}");
                return new MinIOUploadResult
                {
                    Success = false,
                    ErrorMessage = ex.Message
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Genel upload hatası: {fileName}");
                return new MinIOUploadResult
                {
                    Success = false,
                    ErrorMessage = ex.Message
                };
            }
        }

        public async Task<MinIOUploadResult> UploadChunksParallelAsync(string fileName, List<ChunkInfo> chunks, string downloadFolder)
        {
            try
            {
                _logger.LogInformation($"MinIO'ya paralel chunk upload başlıyor: {fileName}");
                await EnsureBucketExistsAndIsPublicAsync();

                // Benzersiz ID oluştur
                string fileId = Guid.NewGuid().ToString("N")[0..8]; // Kısa ID: abc123de

                // Dosya adı + ID birleştir
                string nameWithoutExt = Path.GetFileNameWithoutExtension(fileName);
                string extension = Path.GetExtension(fileName);
                var finalObjectName = $"files/{nameWithoutExt}_{fileId}{extension}";

                // Her chunk'ı ayrı obje olarak paralel yükle
                var uploadTasks = chunks.Select(async chunk =>
                {
                    // Temp chunk'lar için de unique ID kullan
                    var tempObjectName = $"temp/{nameWithoutExt}_{fileId}/chunk_{chunk.Index:D3}";
                    using var chunkStream = File.OpenRead(chunk.FilePath);

                    var putObjectArgs = new PutObjectArgs()
                        .WithBucket(_config.BucketName)
                        .WithObject(tempObjectName)
                        .WithStreamData(chunkStream)
                        .WithObjectSize(chunkStream.Length)
                        .WithContentType("application/octet-stream");

                    await _minioClient.PutObjectAsync(putObjectArgs).ConfigureAwait(false);
                    _logger.LogInformation($"Chunk yüklendi: {tempObjectName} ({FormatBytes(chunk.Size)})");
                    return tempObjectName;
                }).ToArray();

                var uploadedChunkNames = await Task.WhenAll(uploadTasks);

                // Chunk'ları birleştirip final dosya oluştur
                await CombineChunksInMinIOAsync(finalObjectName, uploadedChunkNames, chunks);

                // Temp chunk'ları temizle
                await CleanupTempChunksAsync($"{nameWithoutExt}_{fileId}");

                var totalSize = chunks.Sum(c => c.Size);
                _logger.LogInformation($"Paralel upload tamamlandı: {finalObjectName}");

                return new MinIOUploadResult
                {
                    Success = true,
                    MinIOPath = finalObjectName,
                    FileId = fileId,  // ID'yi ayrıca döndür
                    OriginalFileName = fileName,  // Orijinal dosya adı
                    DownloadUrl = GenerateDownloadUrl(finalObjectName),
                    UploadedChunks = chunks.Count,
                    TotalSize = totalSize,
                    TotalSizeFormatted = FormatBytes(totalSize),
                    UploadedAt = DateTime.Now
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Paralel upload hatası: {fileName}");

                // Hata durumunda temp chunk'ları temizle
                try
                {
                    string nameWithoutExt = Path.GetFileNameWithoutExtension(fileName);
                    await CleanupTempChunksAsync($"{nameWithoutExt}_*"); // Wildcard ile temizlik
                }
                catch (Exception cleanupEx)
                {
                    _logger.LogWarning(cleanupEx, "Temp chunk temizleme hatası");
                }

                return new MinIOUploadResult
                {
                    Success = false,
                    ErrorMessage = ex.Message
                };
            }
        }
        public async Task<string> GetDownloadUrlAsync(string objectName)
        {
            try
            {
                var presignedUrl = await _minioClient.PresignedGetObjectAsync(
                    new PresignedGetObjectArgs()
                        .WithBucket(_config.BucketName)
                        .WithObject(objectName)
                        .WithExpiry(3600)); // 1 saat geçerli

                return presignedUrl;
            }
            catch (Exception ex)
            {
                throw new Exception($"Download URL oluşturma hatası: {ex.Message}");
            }
        }

        private Stream CreateCombinedStream(List<ChunkInfo> chunks)
        {
            var streams = new List<Stream>();

            foreach (var chunk in chunks.OrderBy(c => c.Index))
            {
                streams.Add(File.OpenRead(chunk.FilePath));
            }

            return new ConcatenatedStream(streams);
        }

        private async Task CombineChunksInMinIOAsync(string finalObjectName, string[] chunkNames, List<ChunkInfo> chunks)
        {
            // Chunk'ları sırayla okuyup birleştir
            using var combinedStream = new MemoryStream();

            foreach (var chunkName in chunkNames.OrderBy(x => x))
            {
                var getObjectArgs = new GetObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(chunkName)
                    .WithCallbackStream(stream => stream.CopyTo(combinedStream));

                await _minioClient.GetObjectAsync(getObjectArgs).ConfigureAwait(false);
            }

            combinedStream.Position = 0;

            // Final dosya olarak yükle
            var putObjectArgs = new PutObjectArgs()
                .WithBucket(_config.BucketName)
                .WithObject(finalObjectName)
                .WithStreamData(combinedStream)
                .WithObjectSize(combinedStream.Length)
                .WithContentType("application/octet-stream");

            await _minioClient.PutObjectAsync(putObjectArgs).ConfigureAwait(false);
        }

        public async Task<Stream> DownloadFileAsync(string fileName)
        {
            try
            {
                var objectName = $"files/{fileName}";
                var memoryStream = new MemoryStream();

                var getObjectArgs = new GetObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(objectName)
                    .WithCallbackStream(stream => stream.CopyTo(memoryStream));

                await _minioClient.GetObjectAsync(getObjectArgs).ConfigureAwait(false);

                memoryStream.Position = 0;
                return memoryStream;
            }
            catch (MinioException ex)
            {
                _logger.LogError(ex, $"MinIO download hatası: {fileName}");
                throw;
            }
        }

        public async Task<bool> DeleteFileAsync(string fileName)
        {
            try
            {
                var objectName = $"files/{fileName}";

                var removeObjectArgs = new RemoveObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(objectName);

                await _minioClient.RemoveObjectAsync(removeObjectArgs).ConfigureAwait(false);

                _logger.LogInformation($"Dosya silindi: {objectName}");
                return true;
            }
            catch (MinioException ex)
            {
                _logger.LogError(ex, $"MinIO silme hatası: {fileName}");
                return false;
            }
        }

        public async Task<bool> FileExistsAsync(string fileName)
        {
            try
            {
                var objectName = $"files/{fileName}";

                var statObjectArgs = new StatObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(objectName);

                await _minioClient.StatObjectAsync(statObjectArgs).ConfigureAwait(false);
                return true;
            }
            catch (MinioException)
            {
                return false;
            }
        }

        public async Task<bool> CleanupTempChunksAsync(string fileName)
        {
            try
            {
                var tempPrefix = $"temp/{fileName}/";

                var listObjectsArgs = new ListObjectsArgs()
                    .WithBucket(_config.BucketName)
                    .WithPrefix(tempPrefix);

                var objectsToDelete = new List<string>();

                await foreach (var item in _minioClient.ListObjectsEnumAsync(listObjectsArgs))
                {
                    objectsToDelete.Add(item.Key);
                }

                // Tek tek sil
                foreach (var objectName in objectsToDelete)
                {
                    var removeObjectArgs = new RemoveObjectArgs()
                        .WithBucket(_config.BucketName)
                        .WithObject(objectName);

                    await _minioClient.RemoveObjectAsync(removeObjectArgs).ConfigureAwait(false);
                }

                _logger.LogInformation($"Temp chunk'lar temizlendi: {fileName} ({objectsToDelete.Count} adet)");
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, $"Temp chunk temizleme hatası: {fileName}");
                return false;
            }
        }


        // ❗❗❗ DEĞİŞİKLİK BURADA (AKILLI URL MANTIĞI) ❗❗❗
        // Bu metot artık hangi ortamda olduğuna bakarak URL üretecek.
        private string GenerateDownloadUrl(string objectName)
        {
            string endpoint;

            // 1. Ortam Kontrolü (Local mi, Sunucu mu?)
            // _config.Endpoint (appsettings.json) "127.0.0.1" veya "localhost" içeriyor mu?
            if (_config.Endpoint.Contains("127.0.0.1") || _config.Endpoint.Contains("localhost"))
            {
                // EVET, LOCAL'DEYİZ:
                // _config.PublicEndpoint'i (http://127.0.0.1:9002) KULLAN.
                // (appsettings.Development.json'da her ikisi de aynı olmalı)
                endpoint = _config.PublicEndpoint; // Bu, http://127.0.0.1:9002 olacak
                _logger.LogWarning("Development ortamı algılandı. Local PublicEndpoint ({Endpoint}) public URL olarak kullanılıyor.", endpoint);
            }
            else
            {
                // HAYIR, SUNUCUDAYIZ:
                // Tarayıcının kullanması gereken 'PublicEndpoint'i (https://minio.convoapp.app) KULLAN.
                endpoint = !string.IsNullOrEmpty(_config.PublicEndpoint)
                    ? _config.PublicEndpoint
                    : _config.Endpoint;
            }
            
            // PublicEndpoint ayarı boşsa (olmamalı ama önlem)
            if (string.IsNullOrEmpty(endpoint))
            {
                 _logger.LogError("PublicEndpoint ayarı appsettings.json dosyasında bulunamadı!");
                 endpoint = _config.Endpoint; // Fallback
            }

            // 2. URL'i Oluştur
            // Eğer endpoint zaten protokol içeriyorsa direkt kullan
            if (endpoint.StartsWith("http://") || endpoint.StartsWith("https://"))
            {
                return $"{endpoint}/{_config.BucketName}/{objectName}";
            }

            // Yoksa protokol ekle (Local için http, sunucu için https olabilir)
            var protocol = _config.UseSSL ? "https" : "http";
            return $"{protocol}://{endpoint}/{_config.BucketName}/{objectName}";
        }

        public async Task<string> GeneratePresignedDownloadUrl(string fileName, int expiryHours = 1)
        {
            var objectName = $"files/{fileName}";
            var expiry = expiryHours * 3600;

            var presignedUrl = await _minioClient.PresignedGetObjectAsync(
                new PresignedGetObjectArgs()
                    .WithBucket(_config.BucketName)
                    .WithObject(objectName)
                    .WithExpiry(expiry)
            );

            // ❗ GÜNCELLEME: ImageService'teki 'akıllı düzeltme' mantığını buraya da uyguluyoruz.
            // Bu, 'Presigned' URL'ler için GEREKLİDİR.

            // 1. Ortam Kontrolü (Local mi, Sunucu mu?)
            if (_config.Endpoint.Contains("127.0.0.1") || _config.Endpoint.Contains("localhost"))
            {
                // EVET, LOCAL'DEYİZ:
                // SDK'nın ürettiği URL (örn: http://127.0.0.1:9002/...) zaten doğrudur.
                _logger.LogWarning("Development ortamı algılandı. SDK tarafından üretilen Local Presigned URL kullanılıyor: {Url}", presignedUrl);
                return presignedUrl;
            }
            else
            {
                // HAYIR, SUNUCUDAYIZ:
                // SDK, 'Endpoint' (http://127.0.0.1:9000) kullanarak YANLIŞ URL üretti (örn: http://127.0.0.1:9000/bucket/...).
                // Bu URL'i 'PublicEndpoint' (https://minio.convoapp.app) kullanarak düzeltmeliyiz.

                var internalUri = new Uri(_config.Endpoint); //örn: http://127.0.0.1:9000
                var internalHostAndPort = internalUri.Authority; // örn: 127.0.0.1:9000

                var publicUri = new Uri(_config.PublicEndpoint); // örn: https://minio.convoapp.app
                var publicHostAndPort = publicUri.Authority; // örn: minio.convoapp.app

                // Üretilen URL'deki (örn: http://127.0.0.1:9000/...) 'internal' kısmı 'public' ile değiştir.
                var correctedUrl = presignedUrl.Replace(internalHostAndPort, publicHostAndPort);

                // Ayrıca protokolü de düzelt (http -> https)
                correctedUrl = correctedUrl.Replace(internalUri.Scheme, publicUri.Scheme);
                
                _logger.LogInformation("Production ortamı algılandı. Presigned URL düzeltildi: {Url}", correctedUrl);
                return correctedUrl;
            }
        }

        private string FormatBytes(long bytes)
        {
            string[] sizes = { "B", "KB", "MB", "GB" };
            double len = bytes;
            int order = 0;
            while (len >= 1024 && order < sizes.Length - 1)
            {
                order++;
                len = len / 1024;
            }
            return $"{len:0.##} {sizes[order]}";
        }
    }

    // Helper class: Birden fazla stream'i birleştiren stream
    public class ConcatenatedStream : Stream
    {
        private readonly Queue<Stream> _streams;
        private Stream _currentStream;

        public ConcatenatedStream(IEnumerable<Stream> streams)
        {
            _streams = new Queue<Stream>(streams);
            _currentStream = _streams.Count > 0 ? _streams.Dequeue() : Stream.Null;
        }

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => _streams.Sum(s => s.Length) + _currentStream.Length;
        public override long Position { get; set; }

        public override int Read(byte[] buffer, int offset, int count)
        {
            int totalRead = 0;

            while (count > 0 && _currentStream != null)
            {
                int read = _currentStream.Read(buffer, offset, count);

                if (read == 0)
                {
                    _currentStream?.Dispose();
                    _currentStream = _streams.Count > 0 ? _streams.Dequeue() : null;
                }
                else
                {
                    totalRead += read;
                    offset += read;
                    count -= read;
                    Position += read;
                }
            }

            return totalRead;
        }

        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _currentStream?.Dispose();
                while (_streams.Count > 0)
                {
                    _streams.Dequeue()?.Dispose();
                }
            }
            base.Dispose(disposing);
        }
    }
}