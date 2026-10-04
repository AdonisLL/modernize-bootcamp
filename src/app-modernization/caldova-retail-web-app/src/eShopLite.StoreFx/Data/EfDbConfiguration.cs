using System.Data.Entity;
using System.Data.Entity.Infrastructure;
using System.Data.Entity.SqlServer;
using System.Data.SqlClient;

namespace eShopLite.StoreFx.Data
{
    // EF6 on .NET (Core) has no app.config/Web.config provider registration, so the
    // SQL Server provider and connection factory are registered in code instead.
    public class EfDbConfiguration : DbConfiguration
    {
        public EfDbConfiguration()
        {
            SetProviderServices(SqlProviderServices.ProviderInvariantName, SqlProviderServices.Instance);
            SetProviderFactory(SqlProviderServices.ProviderInvariantName, SqlClientFactory.Instance);
            SetDefaultConnectionFactory(new SqlConnectionFactory());
        }
    }
}
