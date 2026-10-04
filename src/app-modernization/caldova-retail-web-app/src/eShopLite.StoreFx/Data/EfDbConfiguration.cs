using System;
using System.Data.Entity.SqlServer;

namespace eShopLite.StoreFx.Data
{
    // EF6 on .NET (Core) has no app.config/Web.config provider registration, so the SQL Server
    // provider is registered in code. MicrosoftSqlDbConfiguration wires up the
    // Microsoft.Data.SqlClient provider services, factory, and default connection factory, which
    // is what lets the connection string use `Authentication=Active Directory Managed Identity`.
    public class EfDbConfiguration : MicrosoftSqlDbConfiguration
    {
        private const string MicrosoftSqlClientProvider = "Microsoft.Data.SqlClient";

        public EfDbConfiguration()
        {
            // Azure SQL throttles and recycles connections as normal behaviour, and EF6 does not
            // retry by default, so routine platform events would otherwise surface as 500s.
            SetExecutionStrategy(
                MicrosoftSqlClientProvider,
                () => new SqlAzureExecutionStrategy(maxRetryCount: 5, maxDelay: TimeSpan.FromSeconds(10)));
        }
    }
}
