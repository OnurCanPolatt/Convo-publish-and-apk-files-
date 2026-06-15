using Convo.Web.Models;
using Microsoft.AspNetCore.Mvc;
using Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Domain.Models.Download;
using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[Route("api/[controller]")]
[ApiController]
public class ImageController : ControllerBase
{
    private readonly IMinIOService _minIOService;
    private readonly IImageService _imageService;
    private readonly ILogger<ImageController> _logger;

    public ImageController(IMinIOService minIOService, IImageService imageService,
        ILogger<ImageController> logger)
    {
        _minIOService = minIOService;
        _imageService = imageService;
        _logger = logger;
    }

    [HttpPost("upload/{userId}")]
    public async Task<IActionResult> UploadProfileImage(Guid userId)
    {
        try
        {
            // Form content type kontrolü
            if (!Request.HasFormContentType)
            {
                return BadRequest("Form content type yok");
            }

            var file = Request.Form.Files.FirstOrDefault();
            if (file == null || file.Length == 0)
            {
                return BadRequest("Dosya seçilmedi");
            }

            // Dosya türü kontrolü (sadece resim)
            var allowedTypes = new[] { "image/jpeg", "image/jpg", "image/png", "image/gif" };
            if (!allowedTypes.Contains(file.ContentType.ToLower()))
            {
                return BadRequest("Sadece resim dosyaları yüklenebilir");
            }

            // Dosya boyutu kontrolü (10MB)
            if (file.Length > 10 * 1024 * 1024)
            {
                return BadRequest("Dosya boyutu 10MB'dan büyük olamaz");
            }

            // IFormFile'ı FileInput'a çevir
            var fileInput = new FileInput
            {
                FileName = file.FileName,
                ContentType = file.ContentType,
                Size = file.Length,
                OpenStream = (maxSize) =>
                {
                    if (file.Length > maxSize)
                    {
                        throw new InvalidOperationException(
                            $"Dosya boyutu {file.Length} bytes, maximum {maxSize} bytes'ı aşıyor.");
                    }

                    return file.OpenReadStream();
                }
            };

            // MinIO service'i çağır
            var result = await _imageService.UploadImageAsync(userId, fileInput);

            if (result.IsSuccess)
            {
                return Ok(new
                {
                    success = true,
                    message = "Profil fotoğrafı başarıyla yüklendi",
                    data = new
                    {
                        userId = result.UserOrGroupId,
                        originalImageUrl = result.OriginalImageUrl,
                        thumbnailImageUrl = result.ThumbnailImageUrl,
                        fileSize = result.FileSize,
                        uploadedAt = result.UploadedAt
                    }
                });
            }

            return StatusCode(500, new
            {
                success = false,
                message = "Profil fotoğrafı yüklenemedi",
                error = result.ErrorMessage
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Profil fotoğrafı yüklenirken hata oluştu - UserId: {userId}");
            return StatusCode(500, new
            {
                success = false,
                message = "Sunucu hatası",
                error = ex.Message
            });
        }
    }
    [HttpPost("uploadGroupPhoto/{userOrGroupId}")]
public async Task<IActionResult> UploadImage(Guid userOrGroupId)
{
    try
    {
        // 1. Form içeriği ve dosya kontrolü
        if (!Request.HasFormContentType)
        {
            return BadRequest(new { success = false, message = "Form içeriği (multipart/form-data) bulunamadı." });
        }

        var file = Request.Form.Files.FirstOrDefault();
        if (file == null || file.Length == 0)
        {
            return BadRequest(new { success = false, message = "Dosya seçilmedi veya boş." });
        }

        // 2. IFormFile'ı servisinizin anladığı FileInput tipine dönüştürüyoruz
        var fileInput = new FileInput
        {
            FileName = file.FileName,
            ContentType = file.ContentType,
            Size = file.Length,
            OpenStream = (maxSize) => 
            {
                if (file.Length > maxSize)
                {
                    throw new InvalidOperationException($"Dosya boyutu {file.Length} bytes, sınır olan {maxSize} bytes'ı aşıyor.");
                }
                return file.OpenReadStream();
            }
        };

        // 3. Paylaştığın UploadImageAsync metodunu çağırıyoruz
        var result = await _imageService.UploadImageAsync(userOrGroupId, fileInput);

        if (result.IsSuccess)
        {
            return Ok(new
            {
                success = true,
                message = "Resim başarıyla yüklendi",
                data = new
                {
                    id = result.UserOrGroupId,
                    originalImageUrl = result.OriginalImageUrl,
                    thumbnailImageUrl = result.ThumbnailImageUrl,
                    uploadedAt = result.UploadedAt
                }
            });
        }

        return StatusCode(500, new
        {
            success = false,
            message = "Resim yüklenemedi",
            error = result.ErrorMessage
        });
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, $"Resim yüklenirken hata oluştu - ID: {userOrGroupId}");
        return StatusCode(500, new
        {
            success = false,
            message = "Sunucu hatası",
            error = ex.Message
        });
    }
}

    [HttpGet("image/{userId}")]
    public async Task<IActionResult> GetProfileImageUrl(Guid userId)
    {
        try
        {
            var imageUrl = await _imageService.GetImageUrlAsync(userId);

            return Ok(new
            {
                success = true,
                userId = userId,
                imageUrl = imageUrl
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Profil fotoğrafı URL'si alınırken hata - UserId: {userId}");
            return StatusCode(500, new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    [HttpGet("thumbnail/{userId}")]
    public async Task<IActionResult> GetProfileThumbnailUrl(Guid userId)
    {
        try
        {
            var thumbnailUrl = await _imageService.GetImageThumbnailUrlAsync(userId);

            return Ok(new
            {
                success = true,
                userId = userId,
                thumbnailUrl = thumbnailUrl
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Profil thumbnail URL'si alınırken hata - UserId: {userId}");
            return StatusCode(500, new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    [HttpDelete("delete/{userId}")]
    public async Task<IActionResult> DeleteProfileImage(Guid userId)
    {
        try
        {
            var deleted = await _imageService.DeleteImageAsync(userId);

            if (deleted)
            {
                return Ok(new
                {
                    success = true,
                    message = "Profil fotoğrafı başarıyla silindi",
                    userId = userId
                });
            }

            return NotFound(new
            {
                success = false,
                message = "Silinecek profil fotoğrafı bulunamadı",
                userId = userId
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Profil fotoğrafı silinirken hata - UserId: {userId}");
            return StatusCode(500, new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    [HttpGet("check/{userId}")]
    public async Task<IActionResult> CheckProfileImageExists(Guid userId)
    {
        try
        {
            var hasImage = await _imageService.HasProfileImageAsync(userId);

            return Ok(new
            {
                success = true,
                userId = userId,
                hasProfileImage = hasImage
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Profil fotoğrafı kontrol edilirken hata - UserId: {userId}");
            return StatusCode(500, new
            {
                success = false,
                error = ex.Message
            });
        }
    }

    // MinIO genel download URL (diğer dosyalar için)
    [HttpGet("download")]
    public async Task<IActionResult> GetDownloadUrl([FromQuery] string fileName)
    {
        try
        {
            if (string.IsNullOrEmpty(fileName))
            {
                return BadRequest("Dosya adı gerekli");
            }

            var downloadUrl = await _minIOService.GetDownloadUrlAsync(fileName);

            return Ok(new
            {
                success = true,
                fileName = fileName,
                downloadUrl = downloadUrl
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, $"Download URL alınırken hata - FileName: {fileName}");
            return StatusCode(500, new
            {
                success = false,
                error = ex.Message
            });
        }
    }
    // GroupController.cs
    [HttpPost("uploadGroupImage/{groupId}")]
    public async Task<IActionResult> UploadGroupImage([FromRoute] Guid groupId, [FromForm] UploadGroupImageRequest request) // 🚨 FromRoute ve FromForm ekledik
    {
        if (request == null || request.File.Length == 0)
            return BadRequest(new { message = "Dosya boş veya geçersiz." });

        try
        {
            // Flutter'daki http.MultipartFile.fromPath('file', ...) satırındaki 'file' ismiyle 
            // buradaki 'IFormFile file' parametre ismi BİREBİR AYNI olmalıdır.

            var fileInput = new FileInput
            {
                FileName = request.File.FileName,
                ContentType = request.File.ContentType,
                Size = request.File.Length,
                OpenStream = (maxSize) => request.File.OpenReadStream()
            };

            var imageUrl = await _imageService.UploadGroupImageAsync(fileInput, groupId);

            if (string.IsNullOrEmpty(imageUrl))
                return BadRequest(new { message = "Resim yüklenemedi." });

            return Ok(new { imageUrl = imageUrl });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }
}