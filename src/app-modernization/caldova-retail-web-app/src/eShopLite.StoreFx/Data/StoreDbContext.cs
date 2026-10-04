using System.Data.Entity;
using System.Data.Entity.ModelConfiguration.Conventions;
using System.Data.SqlClient;
using System.Linq;

using eShopLite.StoreFx.Models;

namespace eShopLite.StoreFx.Data
{
    public interface IStoreDbContext : System.IDisposable
    {
        DbSet<Product> Products { get; set; }
        DbSet<StoreInfo> Stores { get; set; }
        DbSet<User> Users { get; set; }
        DbSet<Order> Orders { get; set; }
        DbSet<OrderLine> OrderLines { get; set; }

        OrderSummary GetOrderSummary(int userId);

        int SaveChanges();
    }

    [DbConfigurationType(typeof(EfDbConfiguration))]
    public class StoreDbContext : DbContext, IStoreDbContext
    {
        public StoreDbContext(string nameOrConnectionString) : base(nameOrConnectionString)
        {
        }

        // Parameterless constructor for EF6 design-time/migrations tooling.
        public StoreDbContext() : base("name=StoreDbContext")
        {
        }

        public DbSet<Product> Products { get; set; }
        public DbSet<StoreInfo> Stores { get; set; }
        public DbSet<User> Users { get; set; }
        public DbSet<Order> Orders { get; set; }
        public DbSet<OrderLine> OrderLines { get; set; }

        public OrderSummary GetOrderSummary(int userId)
        {
            // [Order] is a reserved word; COUNT(*) guarantees exactly one row even with no orders.
            const string sql =
                "SELECT COUNT(*) AS OrderCount, ISNULL(SUM(Total), 0) AS LifetimeTotal, " +
                "MIN(PlacedUtc) AS FirstOrderUtc, MAX(PlacedUtc) AS LastOrderUtc " +
                "FROM [Order] WHERE UserId = @userId";

            return Database
                .SqlQuery<OrderSummary>(sql, new SqlParameter("@userId", userId))
                .Single();
        }

        protected override void OnModelCreating(DbModelBuilder modelBuilder)
        {
            modelBuilder.Conventions.Remove<PluralizingTableNameConvention>();

            modelBuilder.Entity<User>()
                .HasIndex(u => u.UserName)
                .IsUnique();

            modelBuilder.Entity<Order>()
                .HasMany(o => o.Lines)
                .WithRequired(l => l.Order)
                .HasForeignKey(l => l.OrderId)
                .WillCascadeOnDelete(true);
        }
    }
}
