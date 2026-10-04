using System;
using System.Data.Entity.Migrations;
using System.Linq;

using eShopLite.StoreFx.Data;
using eShopLite.StoreFx.Models;

namespace eShopLite.StoreFx.Migrations
{
    public sealed class Configuration : DbMigrationsConfiguration<StoreDbContext>
    {
        // Deterministic timestamp so seeded rows can be checksum-compared before and after a database migration.
        private static readonly DateTime SeedTimestampUtc = new DateTime(2026, 1, 15, 8, 0, 0, DateTimeKind.Utc);

        public Configuration()
        {
            AutomaticMigrationsEnabled = false;
            AutomaticMigrationDataLossAllowed = false;
            ContextKey = "eShopLite.StoreFx.Data.StoreDbContext";
        }

        protected override void Seed(StoreDbContext context)
        {
            SeedProducts(context);
            SeedStores(context);
            context.SaveChanges();

            SeedUsers(context);
            context.SaveChanges();
        }

        private static void SeedUsers(StoreDbContext context)
        {
            var auth = new Services.AuthService(() => context);

            AddUserIfMissing(context, auth, "alice", "alice@eshoplite.local", "Password1!", "Customer");
            AddUserIfMissing(context, auth, "bob", "bob@eshoplite.local", "Password1!", "Customer");
        }

        private static void AddUserIfMissing(StoreDbContext context, Services.IAuthService auth, string userName, string email, string password, string roles)
        {
            if (context.Users.Any(u => u.UserName == userName))
            {
                return;
            }

            var salt = auth.CreateSalt();

            context.Users.Add(new User
            {
                UserName = userName,
                Email = email,
                PasswordSalt = salt,
                PasswordHash = auth.HashPassword(password, salt),
                Roles = roles,
                IsApproved = true,
                CreatedUtc = SeedTimestampUtc
            });
        }

        private static void SeedProducts(StoreDbContext context)
        {
            context.Products.AddOrUpdate(
                p => p.Name,
                new Product { Name = "Solar Powered Flashlight", Description = "A fantastic product for outdoor enthusiasts", Price = 19.99m, ImageUrl = "product1.png" },
                new Product { Name = "Hiking Poles", Description = "Ideal for camping and hiking trips", Price = 24.99m, ImageUrl = "product2.png" },
                new Product { Name = "Outdoor Rain Jacket", Description = "This product will keep you warm and dry in all weathers", Price = 49.99m, ImageUrl = "product3.png" },
                new Product { Name = "Survival Kit", Description = "A must-have for any outdoor adventurer", Price = 99.99m, ImageUrl = "product4.png" },
                new Product { Name = "Outdoor Backpack", Description = "This backpack is perfect for carrying all your outdoor essentials", Price = 39.99m, ImageUrl = "product5.png" },
                new Product { Name = "Camping Cookware", Description = "This cookware set is ideal for cooking outdoors", Price = 29.99m, ImageUrl = "product6.png" },
                new Product { Name = "Camping Stove", Description = "This stove is perfect for cooking outdoors", Price = 49.99m, ImageUrl = "product7.png" },
                new Product { Name = "Camping Lantern", Description = "This lantern is perfect for lighting up your campsite", Price = 19.99m, ImageUrl = "product8.png" },
                new Product { Name = "Camping Tent", Description = "This tent is perfect for camping trips", Price = 99.99m, ImageUrl = "product9.png" });
        }

        private static void SeedStores(StoreDbContext context)
        {
            context.Stores.AddOrUpdate(
                s => s.Name,
                new StoreInfo { Name = "Outdoor Store", City = "Seattle", State = "WA", Hours = "9am - 5pm" },
                new StoreInfo { Name = "Camping Supplies", City = "Portland", State = "OR", Hours = "10am - 6pm" },
                new StoreInfo { Name = "Hiking Gear", City = "San Francisco", State = "CA", Hours = "11am - 7pm" },
                new StoreInfo { Name = "Fishing Equipment", City = "Los Angeles", State = "CA", Hours = "8am - 4pm" },
                new StoreInfo { Name = "Climbing Gear", City = "Denver", State = "CO", Hours = "9am - 5pm" },
                new StoreInfo { Name = "Cycling Supplies", City = "Austin", State = "TX", Hours = "10am - 6pm" },
                new StoreInfo { Name = "Winter Sports Gear", City = "Salt Lake City", State = "UT", Hours = "11am - 7pm" },
                new StoreInfo { Name = "Water Sports Equipment", City = "Miami", State = "FL", Hours = "8am - 4pm" },
                new StoreInfo { Name = "Outdoor Clothing", City = "New York", State = "NY", Hours = "9am - 5pm" });
        }
    }
}
