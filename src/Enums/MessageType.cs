using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Enums
{
    public enum MessageType
    {
        Text=0,
        Image=1,
        File=2,
        Audio=3,
        Video = 4,
        Location = 5,
        System =6,//(Kulanıcı gruba katıldı gibi,sistemin herkese yolladğı bir mesaj olabilir.)
        Document= 7
    }
}
