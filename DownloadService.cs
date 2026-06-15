using Domain.Interfaces;
using System.Text.Json;
using Domain.Models.Download;
using Domain.Models;
using Microsoft.Extensions.Logging;
using Domain.Entities;
using Domain.Enums;
using Domain.FileDataType;
using Microsoft.JSInterop;

namespace Infrastructure.Services
{
    public class DownloadService : IDownloadService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<DownloadService> _logger;
        private readonly IFileDataService _fileDataService;
        private readonly IJSRuntime JSRuntime;

        // Upload state properties
        private CancellationTokenSource _uploadCancellationTokenSource;
        private DateTime _uploadStartTime;
        private long _uploadedBytes = 0;
        private Timer _uploadProgressTimer;
        private List<int> _completedChunks = new();
        private string _currentUploadSessionId = "";
        private int _lastUploadedChunkIndex = 0;
        private bool _isResuming = false;

        // Download state properties
        private CancellationTokenSource _downloadCancellationTokenSource;
        private DateTime _downloadStartTime;
        private long _downloadedBytes = 0;
        private Timer _downloadProgressTimer;
        private bool _isDownloadPaused = false;
        private bool IsDownloading = false;

        // Upload Events
        public event Action<UploadProgressEventArgs> OnUploadProgressChanged;
        public event Action<string> OnUploadStatusChanged;
        public event Action<string> OnUploadError;
        public event Action OnUploadCompleted;
        public event Action OnUploadCancelled;

        // Download Events  
        public event Action<DownloadProgressEventArgs> OnDownloadProgressChanged;
        public event Action<string> OnDownloadStatusChanged;
        public event Action<string> OnDownloadError;
        public event Action OnDownloadCompleted;
        public event Action OnDownloadCancelled;

        public DownloadService(
            HttpClient httpClient,
            ILogger<DownloadService> logger,
            IFileDataService fileDataService,
            IJSRuntime jsRuntime)
        {
            _httpClient = httpClient;
            _logger = logger;
            _fileDataService = fileDataService;
            JSRuntime = jsRuntime;
            //console write httpclient base address
            _logger.LogWarning($"download service http base adres:{_httpClient.BaseAddress}");
        }

        public async Task<FileUploadResult> UploadFileAsync(IFileInput file, string receiverUserId, Guid senderId)
        {
            try
            {
                if (file.Size > 10L * 1024 * 1024 * 1024)
                {
                    throw new ArgumentException("Dosya boyutu 10 GB'dan büyük olamaz.");
                }

                if (string.IsNullOrEmpty(_currentUploadSessionId))
                {
                    _currentUploadSessionId = Guid.NewGuid().ToString();
                    _lastUploadedChunkIndex = 0;
                    _completedChunks.Clear();
                    _isResuming = false;
                }
                else
                {
                    _isResuming = true;
                    OnUploadStatusChanged?.Invoke("Resume durumu kontrol ediliyor...");
                    await CheckResumeStatusAsync(file.Name);
                }

                if (!_isResuming)
                {
                    _uploadedBytes = 0;
                    _uploadStartTime = DateTime.Now;
                }
                else
                {
                    var resumeBytes = _completedChunks.Count * 1024 * 1024;
                    _uploadedBytes = resumeBytes;
                    var progressPercentage = (double)_uploadedBytes / file.Size * 100;
                    OnUploadProgressChanged?.Invoke(new UploadProgressEventArgs
                    {
                        ProgressPercentage = progressPercentage,
                        UploadedBytes = _uploadedBytes,
                        TotalBytes = file.Size
                    });
                    OnUploadStatusChanged?.Invoke($"Devam ettiriliyor... Parça {_lastUploadedChunkIndex + 1}'den");
                }

                _uploadCancellationTokenSource = new CancellationTokenSource();
                _uploadProgressTimer = new Timer(UpdateUploadSpeedAndTime, file, 1000, 1000);

                var result = await ProcessFileWithChunksAsync(file, senderId);
                if (result.Success && result.Message != null)
                {
                    result.Message.ReceiverId = Guid.Parse(receiverUserId);
                }

                OnUploadStatusChanged?.Invoke("Tamamlandı!");
                OnUploadProgressChanged?.Invoke(new UploadProgressEventArgs
                {
                    ProgressPercentage = 100,
                    UploadedBytes = file.Size,
                    TotalBytes = file.Size
                });

                OnUploadCompleted?.Invoke();
                ResetUploadState();

                return result;
            }
            catch (OperationCanceledException)
            {
                OnUploadStatusChanged?.Invoke("İptal edildi");
                OnUploadCancelled?.Invoke();
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Dosya yükleme hatası: {FileName}", file.Name);
                OnUploadError?.Invoke(ex.Message);
                throw;
            }
            finally
            {
                _uploadProgressTimer?.Dispose();
            }
        }

        private async Task<FileUploadResult> ProcessFileWithChunksAsync(IFileInput file, Guid senderId)
        {
            // 1️⃣ FileData'yı manuel oluşturuyoruz ki stream'e kimse dokunmasın
            var fileData = new Domain.FileDataType.FileData
            {
                FileName = file.Name,
                ContentType = file.ContentType,
                FileSize = file.Size,
                UploadedAt = DateTime.UtcNow,
                FileType = file.ContentType.StartsWith("image/") ? Domain.Enums.MessageType.Image : Domain.Enums.MessageType.Document
            };

            // 2️⃣ Stream'i burada açıyoruz ve DOĞRUDAN gönderme metoduna paslıyoruz
            using var stream = file.OpenReadStream(maxAllowedSize: 10L * 1024 * 1024 * 1024);
    
            // 🚨 DİKKAT: stream.Position = 0; burada ASLA olmamalı.
    
            var downloadResult = await SendFileInChunksAsync(stream, file);

            var fileMessage = CreateFileMessage(fileData, file, downloadResult, senderId);

            return new FileUploadResult { Success = true, Message = fileMessage };
        }
private async Task<DownloadResult> SendFileInChunksAsync(Stream stream, IFileInput file)
{
    const int chunkSize = 1024 * 1024; // 1MB parça boyutu
    var totalSize = file.Size;
    var totalChunks = (int)Math.Ceiling((double)totalSize / chunkSize);
    
    // Not: Resume için 'startChunkIndex' kullanıyoruz ancak stream.Position kullanmıyoruz.
    var startChunkIndex = _isResuming ? _lastUploadedChunkIndex + 1 : 0;

    for (int chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++)
    {
        if (_uploadCancellationTokenSource.Token.IsCancellationRequested) break;

        // Duraklatma kontrolü
        while (IsPaused && !_uploadCancellationTokenSource.Token.IsCancellationRequested)
        {
            await Task.Delay(100);
        }

        // 🚨 RESUME MANTIĞI (GÜVENLİ):
        // Position atama yapılamadığı için, eski parçaları 'boş okuma' ile geçiyoruz.
        if (chunkIndex < startChunkIndex)
        {
            var skipBuffer = new byte[chunkSize];
            var bytesToSkip = (int)Math.Min(chunkSize, totalSize - (long)chunkIndex * chunkSize);
            int skipped = 0;
            while (skipped < bytesToSkip)
            {
                var read = await stream.ReadAsync(skipBuffer, 0, bytesToSkip - skipped, _uploadCancellationTokenSource.Token);
                if (read == 0) break;
                skipped += read;
            }
            continue; 
        }

        // 🚨 MEVCUT PARÇAYI HESAPLA (Position kullanmadan)
        var currentOffset = (long)chunkIndex * chunkSize;
        var currentChunkSize = (int)Math.Min(chunkSize, totalSize - currentOffset);

        var chunkData = new byte[currentChunkSize];
        int bytesReadTotal = 0;

        // 🚨 OKUMA DÖNGÜSÜ:
        // Tarayıcı akışları bazen parçalı veri gönderir, buffer dolana kadar okuyoruz.
        while (bytesReadTotal < currentChunkSize)
        {
            var read = await stream.ReadAsync(
                chunkData, 
                bytesReadTotal, 
                currentChunkSize - bytesReadTotal, 
                _uploadCancellationTokenSource.Token);

            if (read == 0) break; 
            bytesReadTotal += read;
        }

        if (bytesReadTotal > 0)
        {
            try
            {
                // API'ye gönder
                await SendChunkToAPIAsync(chunkData, bytesReadTotal, file.Name, chunkIndex, totalChunks);
                
                _completedChunks.Add(chunkIndex);
                _lastUploadedChunkIndex = chunkIndex;
                _uploadedBytes += bytesReadTotal;

                // UI Güncelleme
                var progressPercentage = (double)_uploadedBytes / totalSize * 100;
                OnUploadProgressChanged?.Invoke(new UploadProgressEventArgs
                {
                    ProgressPercentage = progressPercentage,
                    UploadedBytes = _uploadedBytes,
                    TotalBytes = totalSize
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Parça {Index} gönderilirken hata.", chunkIndex);
                throw new Exception($"Parça {chunkIndex + 1} gönderilemedi: {ex.Message}");
            }
        }

        // Akışı canlı tutmak için gecikmeyi minimumda tutuyoruz.
        await Task.Yield(); 
    }

    if (_completedChunks.Count >= totalChunks)
    {
        return await CompleteFileUploadAsync(file.Name);
    }

    return null;
}

    private async Task SendChunkToAPIAsync(byte[] chunkData, int chunkSize, string fileName, int chunkIndex, int totalChunks)
{
    // ✅ Debug logs ekle
    Console.WriteLine($"📤 Sending chunk {chunkIndex + 1}/{totalChunks}");
    Console.WriteLine($"📊 HttpClient BaseAddress: {_httpClient.BaseAddress}");
    
    using var content = new MultipartFormDataContent();
    content.Add(new ByteArrayContent(chunkData, 0, chunkSize), "chunk", $"chunk_{chunkIndex}");
    content.Add(new StringContent(fileName), "fileName");
    content.Add(new StringContent(chunkIndex.ToString()), "chunkIndex");
    content.Add(new StringContent(chunkSize.ToString()), "chunkSize");
    content.Add(new StringContent(_currentUploadSessionId), "sessionId");
    content.Add(new StringContent(totalChunks.ToString()), "totalChunks");

    try
    {
        // ✅ DÜZELTME: Başındaki "/" kaldırıldı
        var response = await _httpClient.PostAsync("api/Download/chunk", content, _uploadCancellationTokenSource.Token);
        
        Console.WriteLine($"📥 Response Status: {response.StatusCode}");

        if (!response.IsSuccessStatusCode)
        {
            var errorContent = await response.Content.ReadAsStringAsync();
            Console.WriteLine($"❌ Error: {errorContent}");
            throw new Exception($"Chunk {chunkIndex} gönderilemedi: {response.StatusCode} - {errorContent}");
        }

        var responseContent = await response.Content.ReadAsStringAsync();
        Console.WriteLine($"✅ Chunk {chunkIndex + 1} başarıyla gönderildi");
        
        var result = JsonSerializer.Deserialize<ChunkSaveResponse>(responseContent, 
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        if (result != null && result.Success)
        {
            OnUploadProgressChanged?.Invoke(new UploadProgressEventArgs
            {
                ProgressPercentage = result.ProgressPercentage,
                CompletedChunks = result.CompletedChunks,
                TotalChunks = result.TotalChunks
            });
            OnUploadStatusChanged?.Invoke($"Gönderiliyor... {result.CompletedChunks}/{result.TotalChunks}");
        }
    }
    catch (HttpRequestException ex)
    {
        Console.WriteLine($"❌ HTTP Request Error: {ex.Message}");
        Console.WriteLine($"❌ Inner Exception: {ex.InnerException?.Message}");
        throw new Exception($"Bağlantı hatası: {ex.Message}");
    }
}

private async Task<DownloadResult> CompleteFileUploadAsync(string fileName)
{
    OnUploadStatusChanged?.Invoke("Dosya birleştiriliyor...");

    Console.WriteLine($"🔧 Completing file: {fileName}, Session: {_currentUploadSessionId}");

    // ✅ DÜZELTME: Complete endpoint kullan
    var completeData = new { SessionId = _currentUploadSessionId, FileName = fileName };
    var content = new StringContent(
        System.Text.Json.JsonSerializer.Serialize(completeData),
        System.Text.Encoding.UTF8,
        "application/json"
    );

    var completeResponse = await _httpClient.PostAsync(
        "api/Download/complete",
        content,
        _uploadCancellationTokenSource.Token
    );

    Console.WriteLine($"📥 Complete Response: {completeResponse.StatusCode}");

    if (!completeResponse.IsSuccessStatusCode)
    {
        var errorContent = await completeResponse.Content.ReadAsStringAsync();
        Console.WriteLine($"❌ Complete Error: {errorContent}");
        throw new Exception($"Dosya birleştirilemedi: {completeResponse.StatusCode} - {errorContent}");
    }

    var result = await completeResponse.Content.ReadAsStringAsync();
    Console.WriteLine($"✅ File completed successfully");

    var downloadResult = System.Text.Json.JsonSerializer.Deserialize<DownloadResult>(result,
        new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });

    return downloadResult ?? new DownloadResult { Success = true, FileName = fileName };
}
private Message CreateFileMessage(FileData fileData, IFileInput file, DownloadResult downloadResult, Guid senderId)
{
    var messageContent = _fileDataService.GetMessageContentForFileType(fileData.FileType, fileData.FileName);

    // MinIOPath varsa fileData'ya kaydet
    if (fileData != null && downloadResult?.MinIOResult?.MinIOPath != null)
    {
        fileData.FilePath = downloadResult.MinIOResult.MinIOPath; 
    }

    string fileUrl;

    if (!string.IsNullOrEmpty(downloadResult?.MinIOResult?.DownloadUrl))
    {
        fileUrl = downloadResult.MinIOResult.DownloadUrl;
    }
    else
    {
        // Fallback: backend download endpoint
        fileUrl = $"https://convoapp.app/api/Download/download?filePath={Uri.EscapeDataString(fileData.FilePath)}";
    }

    return new Message
    {
        Id = Guid.NewGuid(),
        Content = messageContent,
        Type = fileData.FileType,
        SenderId = senderId,
        SentAt = DateTime.Now,
        IsRead = false,
        FileData = fileData,
        FileUrl = fileUrl
    };
}

        private async Task CheckResumeStatusAsync(string fileName)
        {
            try
            {
                Console.WriteLine($"🔄 Checking resume status for session: {_currentUploadSessionId}");
        
                // ✅ DÜZELTME: Başındaki "/" kaldırıldı
                var response = await _httpClient.GetAsync(
                    $"api/Download/resume-status?sessionId={_currentUploadSessionId}&fileName={Uri.EscapeDataString(fileName)}"
                );

                if (response.IsSuccessStatusCode)
                {
                    var resumeData = await response.Content.ReadAsStringAsync();
                    var resumeInfo = JsonSerializer.Deserialize<ResumeStatusResponse>(resumeData, 
                        new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                    if (resumeInfo != null)
                    {
                        _completedChunks = resumeInfo.CompletedChunkIndexes ?? new List<int>();
                        _lastUploadedChunkIndex = _completedChunks.Any() ? _completedChunks.Max() : 0;
                        Console.WriteLine($"✅ Resume: {_completedChunks.Count} chunks already uploaded");
                    }
                }
                else
                {
                    Console.WriteLine($"⚠️ No resume data found, starting fresh");
                    _isResuming = false;
                    _currentUploadSessionId = Guid.NewGuid().ToString();
                    _completedChunks.Clear();
                    _lastUploadedChunkIndex = 0;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Resume kontrolü hatası");
                _isResuming = false;
            }
        }

        #region Upload Controls

        public bool IsPaused { get; private set; }

        public void PauseUpload()
        {
            IsPaused = true;
            OnUploadStatusChanged?.Invoke("Duraklatıldı");
        }

        public void ResumeUpload()
        {
            IsPaused = false;
            OnUploadStatusChanged?.Invoke("Devam ediyor...");
        }

        public async Task CancelUploadAsync()
        {
            _uploadCancellationTokenSource?.Cancel();
            OnUploadStatusChanged?.Invoke("İptal edildi");

            if (!string.IsNullOrEmpty(_currentUploadSessionId))
            {
                try
                {
                    Console.WriteLine($"🧹 Cleaning up session: {_currentUploadSessionId}");
            
                    // ✅ DÜZELTME: Başındaki "/" kaldırıldı
                    await _httpClient.DeleteAsync($"api/Download/cleanup/{_currentUploadSessionId}");
            
                    Console.WriteLine($"✅ Session cleaned up");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Session temizleme hatası");
                }
            }

            ResetUploadState();
            OnUploadCancelled?.Invoke();
        }

        public async Task RetryUploadAsync(IFileInput file, string receiverUserId, Guid senderId)
        {
            OnUploadError?.Invoke("");
            await UploadFileAsync(file, receiverUserId, senderId);
        }

        private void ResetUploadState()
        {
            IsPaused = false;
            _uploadedBytes = 0;
            _currentUploadSessionId = "";
            _lastUploadedChunkIndex = 0;
            _completedChunks.Clear();
            _isResuming = false;
            _uploadCancellationTokenSource?.Cancel();
            _uploadProgressTimer?.Dispose();
        }

        #endregion

        #region Download Methods

        public async Task DownloadFileAsync(string fileUrl, string fileName)
        {
            try
            {
                IsDownloading = true;
                _downloadedBytes = 0;
                _downloadStartTime = DateTime.Now;
                _downloadCancellationTokenSource = new CancellationTokenSource();

                OnDownloadStatusChanged?.Invoke("İndirme başlıyor...");

                var fileInfo = await GetFileInfoAsync(fileUrl);

                if (fileInfo.ContentLength.HasValue && fileInfo.ContentLength > 0)
                {
                    await DownloadFileWithProgressAsync(fileUrl, fileName, fileInfo.ContentLength.Value);
                }
                else
                {
                    await DownloadFileDirectAsync(fileUrl, fileName);
                }

                OnDownloadStatusChanged?.Invoke("İndirme tamamlandı!");
                OnDownloadCompleted?.Invoke();
            }
            catch (OperationCanceledException)
            {
                OnDownloadStatusChanged?.Invoke("İndirme iptal edildi");
                OnDownloadCancelled?.Invoke();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Dosya indirme hatası: {FileName}", fileName);
                OnDownloadError?.Invoke($"İndirme hatası: {ex.Message}");
            }
            finally
            {
                IsDownloading = false;
                _downloadProgressTimer?.Dispose();
            }
        }

        public async Task<byte[]> DownloadFileAsBytesAsync(string fileUrl)
        {
            try
            {
                OnDownloadStatusChanged?.Invoke("Dosya indiriliyor...");
                var response = await _httpClient.GetAsync(fileUrl);
                response.EnsureSuccessStatusCode();

                var bytes = await response.Content.ReadAsByteArrayAsync();
                OnDownloadStatusChanged?.Invoke("İndirme tamamlandı");
                return bytes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Dosya byte array olarak indirilemedi: {FileUrl}", fileUrl);
                OnDownloadError?.Invoke($"İndirme hatası: {ex.Message}");
                return Array.Empty<byte>();
            }
        }

        public async Task<Stream> DownloadFileAsStreamAsync(string fileUrl)
        {
            try
            {
                var response = await _httpClient.GetAsync(fileUrl, HttpCompletionOption.ResponseHeadersRead);
                response.EnsureSuccessStatusCode();
                return await response.Content.ReadAsStreamAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Dosya stream olarak indirilemedi: {FileUrl}", fileUrl);
                OnDownloadError?.Invoke($"İndirme hatası: {ex.Message}");
                return new MemoryStream();
            }
        }

        private async Task<(long? ContentLength, string ContentType)> GetFileInfoAsync(string fileUrl)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Head, fileUrl);
                var response = await _httpClient.SendAsync(request);

                return (
                    ContentLength: response.Content.Headers.ContentLength,
                    ContentType: response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream"
                );
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Dosya bilgileri alınamadı, direct download yapılacak");
                return (null, "application/octet-stream");
            }
        }

        private async Task DownloadFileWithProgressAsync(string fileUrl, string fileName, long totalSize)
        {
            OnDownloadStatusChanged?.Invoke("İndirme başlıyor...");
            _downloadProgressTimer = new Timer(UpdateDownloadSpeedAndTime, new { fileName, totalSize }, 1000, 1000);

            using var response = await _httpClient.GetAsync(fileUrl, HttpCompletionOption.ResponseHeadersRead, _downloadCancellationTokenSource.Token);
            response.EnsureSuccessStatusCode();

            var buffer = new byte[8192];
            using var contentStream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new MemoryStream();

            int bytesRead;
            while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length, _downloadCancellationTokenSource.Token)) > 0)
            {
                while (_isDownloadPaused && !_downloadCancellationTokenSource.Token.IsCancellationRequested)
                {
                    await Task.Delay(100);
                }

                if (_downloadCancellationTokenSource.Token.IsCancellationRequested) break;

                await fileStream.WriteAsync(buffer, 0, bytesRead);
                _downloadedBytes += bytesRead;

                var progressPercentage = (double)_downloadedBytes / totalSize * 100;
                OnDownloadProgressChanged?.Invoke(new DownloadProgressEventArgs
                {
                    ProgressPercentage = progressPercentage,
                    DownloadedBytes = _downloadedBytes,
                    TotalBytes = totalSize,
                    FileName = fileName
                });
            }

            if (!_downloadCancellationTokenSource.Token.IsCancellationRequested)
            {
                await SaveFileAsync(fileStream.ToArray(), fileName);
            }
        }

        private async Task DownloadFileDirectAsync(string fileUrl, string fileName)
        {
            var bytes = await _httpClient.GetByteArrayAsync(fileUrl);
            await SaveFileAsync(bytes, fileName);
        }

        private async Task SaveFileAsync(byte[] fileData, string fileName)
        {
            try
            {
                var base64 = Convert.ToBase64String(fileData);
                await JSRuntime.InvokeVoidAsync("saveFileFromBase64", base64, fileName);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Dosya kaydetme hatası: {FileName}", fileName);
                throw;
            }
        }

        #endregion

        #region Download Controls

        public void PauseDownload()
        {
            _isDownloadPaused = true;
            OnDownloadStatusChanged?.Invoke("İndirme duraklatıldı");
        }

        public void ResumeDownload()
        {
            _isDownloadPaused = false;
            OnDownloadStatusChanged?.Invoke("İndirme devam ediyor...");
        }

        public async Task CancelDownloadAsync()
        {
            _downloadCancellationTokenSource?.Cancel();
            OnDownloadStatusChanged?.Invoke("İndirme iptal edildi");
            IsDownloading = false;
            OnDownloadCancelled?.Invoke();
        }

        #endregion

        #region Progress Tracking

        private void UpdateUploadSpeedAndTime(object state)
        {
            if (IsPaused) return;

            var file = state as IFileInput;
            if (file == null) return;

            var elapsed = DateTime.Now - _uploadStartTime;
            if (elapsed.TotalSeconds > 0 && _uploadedBytes > 0)
            {
                var speed = _uploadedBytes / elapsed.TotalSeconds;
                var remainingBytes = file.Size - _uploadedBytes;
                var remainingSeconds = remainingBytes / speed;

                OnUploadProgressChanged?.Invoke(new UploadProgressEventArgs
                {
                    ProgressPercentage = (double)_uploadedBytes / file.Size * 100,
                    UploadedBytes = _uploadedBytes,
                    TotalBytes = file.Size,
                    Speed = FormatSpeed(speed),
                    RemainingTime = FormatTime(TimeSpan.FromSeconds(remainingSeconds))
                });
            }
        }

        private void UpdateDownloadSpeedAndTime(object state)
        {
            if (_isDownloadPaused) return;

            var fileInfo = state as dynamic;
            if (fileInfo == null) return;

            var elapsed = DateTime.Now - _downloadStartTime;
            if (elapsed.TotalSeconds > 0 && _downloadedBytes > 0)
            {
                var speed = _downloadedBytes / elapsed.TotalSeconds;
                var remainingBytes = (long)fileInfo.totalSize - _downloadedBytes;
                var remainingSeconds = remainingBytes / speed;

                OnDownloadProgressChanged?.Invoke(new DownloadProgressEventArgs
                {
                    ProgressPercentage = (double)_downloadedBytes / (long)fileInfo.totalSize * 100,
                    DownloadedBytes = _downloadedBytes,
                    TotalBytes = (long)fileInfo.totalSize,
                    Speed = FormatSpeed(speed),
                    RemainingTime = FormatTime(TimeSpan.FromSeconds(remainingSeconds)),
                    FileName = (string)fileInfo.fileName
                });
            }
        }

        private string FormatSpeed(double bytesPerSecond) => _fileDataService.GetFileSize((long)bytesPerSecond) + "/s";

        private string FormatTime(TimeSpan time)
        {
            if (time.TotalDays >= 1)
                return $"{(int)time.TotalDays}g {time.Hours}s";
            else if (time.TotalHours >= 1)
                return $"{time.Hours}s {time.Minutes}d";
            else
                return $"{time.Minutes}d {time.Seconds}s";
        }

        #endregion

        #region File Utilities

        public string GetFileIcon(string fileName) => _fileDataService.GetFileIcon(fileName);
        public string GetFileSize(long bytes) => _fileDataService.GetFileSize(bytes);
        public string GetFileExtension(string fileName) => _fileDataService.GetFileExtension(fileName);

        #endregion

        public void Dispose()
        {
            _uploadCancellationTokenSource?.Cancel();
            _uploadCancellationTokenSource?.Dispose();
            _uploadProgressTimer?.Dispose();

            _downloadCancellationTokenSource?.Cancel();
            _downloadCancellationTokenSource?.Dispose();
            _downloadProgressTimer?.Dispose();
        }
    }
}