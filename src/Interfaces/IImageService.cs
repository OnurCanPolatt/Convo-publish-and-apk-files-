using Domain.Models.Download;
using Domain.Models.MinIO;

namespace Domain.Interfaces
{
    public interface IImageService
    {
        /// <summary>
        /// Kullanıcı profil fotoğrafını MinIO'ya yükler
        /// </summary>
        Task<ImageResult> UploadImageAsync(Guid userOrGroupId, FileInput profileImage);

        /// <summary>
        /// Kullanıcının profil fotoğrafının URL'sini getirir
        /// </summary>
        Task<string> GetImageUrlAsync(Guid userOrGroupId);
        Task<Dictionary<Guid, string>> GetMultipleProfileImageUrlsAsync(List<Guid> userOrGroupIds);
        Task<string> GetGroupImageUrlAsync(Guid groupId);

        /// <summary>
        /// Kullanıcının profil fotoğrafının thumbnail URL'sini getirir
        /// </summary>
        Task<string> GetImageThumbnailUrlAsync(Guid userOrGroupId);

        /// <summary>
        /// Kullanıcının profil fotoğrafını siler
        /// </summary>
        Task<bool> DeleteImageAsync(Guid userOrGroupId);

        /// <summary>
        /// Kullanıcının profil fotoğrafı var mı kontrol eder
        /// </summary>
        Task<bool> HasProfileImageAsync(Guid userOrGroupId);
        Task<string> UploadGroupImageAsync(FileInput file, Guid groupId);
    }
}
