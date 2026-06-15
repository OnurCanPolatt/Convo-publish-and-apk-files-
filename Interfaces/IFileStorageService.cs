using Convo.Application.Common.Models;
using System.IO;
using System.Threading.Tasks;

namespace Convo.Application.Common.Interfaces
{
    public interface IFileStorageService
    {
        Task<FileUploadResult> UploadFileAsync(string fileName, Stream fileStream, string contentType);
        Task<bool> DeleteFileAsync(string fileId);
        Task<string> GetDownloadUrlAsync(string fileId);
    }
}