using Microsoft.AspNetCore.Mvc;
using System.Collections.Concurrent;
using Microsoft.AspNetCore.Cors;
using Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;

using Domain.Models.MinIO;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[EnableCors("AllowApiCalls")]
[ApiController]
[Route("api/[controller]")]
public class DownloadController : ControllerBase
{
    private readonly IMinIOService _minioService;
    // Session bazlı chunk storage
    private static readonly ConcurrentDictionary<string, List<byte[]>> _chunkStorage = new();

    public DownloadController(IMinIOService minioService)
    {
        _minioService=minioService;
    }

    [HttpPost("chunk")]
    public async Task<IActionResult> UploadChunk([FromForm] ChunkUploadModel model)
    {
        try
        {
            Console.WriteLine($"📤 Chunk alındı: {model.ChunkIndex}/{model.TotalChunks - 1}");

            // Session için chunk listesi oluştur
            if (!_chunkStorage.ContainsKey(model.SessionId))
            {
                _chunkStorage[model.SessionId] = new List<byte[]>(new byte[model.TotalChunks][]);
            }

            // Chunk'ı kaydet
            var chunks = _chunkStorage[model.SessionId];

            using var ms = new MemoryStream();
            await model.Chunk.CopyToAsync(ms);
            chunks[model.ChunkIndex] = ms.ToArray();

            Console.WriteLine($"✅ Chunk {model.ChunkIndex} kaydedildi");

            return Ok(new { success = true, chunkIndex = model.ChunkIndex });
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Chunk upload hatası: {ex.Message}");
            return StatusCode(500, new { error = ex.Message });
        }
    }

        [HttpGet("download")]
    public IActionResult DownloadFile([FromQuery] string filePath)
    {
        try
        {
            // filePath = "guid_dosya.pdf" formatında geliyor
            var rootPath = Directory.GetCurrentDirectory();
            var downloadsPath = Path.Combine(rootPath, "Downloads");
            var fullPath = Path.Combine(downloadsPath, filePath);

            if (!System.IO.File.Exists(fullPath))
            {
                Console.WriteLine($"❌ Dosya bulunamadı: {fullPath}");
                return NotFound("Dosya bulunamadı");
            }

            // Orijinal dosya adını al (guid_ kısmını kaldır)
            var originalFileName = filePath.Contains('_')
                ? filePath.Substring(filePath.IndexOf('_') + 1)
                : filePath;

            var fileBytes = System.IO.File.ReadAllBytes(fullPath);
            var contentType = "application/octet-stream";

            Console.WriteLine($"✅ Dosya indiriliyor: {originalFileName}");

            return File(fileBytes, contentType, originalFileName);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Download hatası: {ex.Message}");
            return StatusCode(500, new { error = ex.Message });
        }
    }

  [HttpPost("complete")]
    public async Task<IActionResult> CompleteUpload([FromBody] CompleteUploadModel model)
    {
        if (!_chunkStorage.TryRemove(model.SessionId, out var chunks))
        {
            return NotFound("Session bulunamadı");
        }

        string fullPath = null; // Dosya yolunu en üstte tanımla
        try
        {
            // 1. Chunk'ları birleştir
            var completeFile = chunks.SelectMany(c => c).ToArray();
            long fileSize = completeFile.LongLength;

            // 2. Diske yaz (SENİN İSTEDİĞİN ADIM)
            var fileName = Path.GetFileName(model.FileName);
            var uniqueFileName = $"{Guid.NewGuid()}_{fileName}";
            var rootPath = Directory.GetCurrentDirectory();
            var downloadsPath = Path.Combine(rootPath, "Downloads");

            if (!Directory.Exists(downloadsPath))
                Directory.CreateDirectory(downloadsPath);

            fullPath = Path.Combine(downloadsPath, uniqueFileName);

            // Dosyayı diske yaz
            await System.IO.File.WriteAllBytesAsync(fullPath, completeFile);
            
            Console.WriteLine($"✅ Dosya diske kaydedildi (staging): {uniqueFileName}");

            // 3. YENİ: Diskteki dosyayı MinIO'ya yolla
            MinIOUploadResult minioResult;
            try
            {
                // Diske yazdığımız dosyayı okumak için bir stream aç
                using var fileStream = new FileStream(fullPath, FileMode.Open, FileAccess.Read);
                
                minioResult = await _minioService.UploadFileAsync(
                    fileStream,
                    fileSize,
                    model.FileName,
                    "application/octet-stream" // Dilersen model ile MimeType da taşıyabilirsin
                );
            }
            catch (Exception minioEx)
            {
                Console.WriteLine($"❌ MinIO yükleme hatası: {minioEx.Message}");
                // Hata oluşursa diske yazdığımız dosyayı SİLMİYORUZ (kurtarılabilir)
                return StatusCode(500, new { error = "Dosya MinIO'ya yüklenirken hata oluştu." });
            }

            // MinIO'dan başarısız sonuç dönerse
            if (minioResult == null || !minioResult.Success)
            {
                Console.WriteLine($"❌ MinIO servis hatası: {minioResult?.ErrorMessage}");
                return StatusCode(500, new { error = $"MinIO servis hatası: {minioResult?.ErrorMessage}" });
            }

            Console.WriteLine($"✅ Dosya MinIO'ya yüklendi: {minioResult.MinIOPath}");
            
            // 4. YENİ: MinIO'ya yüklendiyse, yerel dosyayı sil
            // (Bu adım kritik değil, başarısız olursa sadece logla, request'i durdurma)
            try
            {
                System.IO.File.Delete(fullPath);
                Console.WriteLine($"✅ Yerel kopya (staging) silindi: {uniqueFileName}");
            }
            catch (Exception deleteEx)
            {
                Console.WriteLine($"⚠️ Yerel kopya silinemedi: {uniqueFileName}. Hata: {deleteEx.Message}");
            }

            // 5. YENİ: MinIO URL'sini istemciye döndür
            return Ok(new
            {
                Success = true,
                FileName = model.FileName,
                FileSize = fileSize,
                MinIOResult = new
                {
                    MinIOPath = minioResult.MinIOPath,
                    Success = minioResult.Success,
                    DownloadUrl = minioResult.DownloadUrl // ❗ Artık burası MinIO'nun public URL'si
                }
            });
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Complete upload genel hatası: {ex.Message}");
            
            // Eğer dosya yazıldıysa ama başka bir hata olduysa,
            // yine de temizlik yapmayı deneyebiliriz (opsiyonel)
            // if (fullPath != null && System.IO.File.Exists(fullPath))
            // {
            //    System.IO.File.Delete(fullPath);
            // }

            return StatusCode(500, new { error = ex.Message });
        }
    }
}

public class ChunkUploadModel
{
    public IFormFile Chunk { get; set; } = null!;
    public string FileName { get; set; } = string.Empty;
    public int ChunkIndex { get; set; }
    public int ChunkSize { get; set; }
    public string SessionId { get; set; } = string.Empty;
    public int TotalChunks { get; set; }
}

public class CompleteUploadModel
{
    public string SessionId { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
}
