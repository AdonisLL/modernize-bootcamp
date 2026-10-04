using System;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

using eShopLite.StoreFx.Data;
using eShopLite.StoreFx.Models;

namespace eShopLite.StoreFx.Services
{
    public interface IAuthService
    {
        User ValidateUser(string userName, string password);
        string HashPassword(string password, string salt);
        string CreateSalt();
    }

    /// <summary>
    /// Legacy membership-style authentication. The salted-SHA1 scheme mirrors what
    /// SqlMembershipProvider did and is intentionally left as-is for the modernization lab.
    /// </summary>
    public class AuthService : IAuthService
    {
        private readonly IStoreDbContext _context;

        public AuthService(IStoreDbContext context)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));
        }

        public User ValidateUser(string userName, string password)
        {
            if (string.IsNullOrWhiteSpace(userName) || string.IsNullOrEmpty(password))
            {
                return null;
            }

            var user = _context.Users.FirstOrDefault(u => u.UserName == userName);
            if (user == null || !user.IsApproved)
            {
                return null;
            }

            var hash = HashPassword(password, user.PasswordSalt);

            return string.Equals(hash, user.PasswordHash, StringComparison.OrdinalIgnoreCase) ? user : null;
        }

        public string HashPassword(string password, string salt)
        {
            using (var sha1 = SHA1.Create())
            {
                var bytes = Encoding.UTF8.GetBytes(salt + password);
                return BitConverter.ToString(sha1.ComputeHash(bytes)).Replace("-", string.Empty);
            }
        }

        public string CreateSalt()
        {
            var buffer = RandomNumberGenerator.GetBytes(16);

            return Convert.ToBase64String(buffer);
        }
    }
}
