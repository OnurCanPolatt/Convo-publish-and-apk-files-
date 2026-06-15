using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Interfaces
{
    public interface IFileInput
    {
        string Name { get; }
        long Size { get; }
        string ContentType { get; }
        Stream OpenReadStream(long maxAllowedSize = 512000);
    }
}
