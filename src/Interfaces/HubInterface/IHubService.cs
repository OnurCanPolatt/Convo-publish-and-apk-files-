namespace Domain.Interfaces.HubInterface;

public interface IHubService
{
    Task<string[]> GetReallyOnlineUsersListAsync();
}