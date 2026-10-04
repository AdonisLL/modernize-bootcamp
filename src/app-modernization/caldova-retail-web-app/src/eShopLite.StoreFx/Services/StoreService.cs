using System;
using System.Collections.Generic;
using System.Linq;

using eShopLite.StoreFx.Data;
using eShopLite.StoreFx.Models;

namespace eShopLite.StoreFx.Services
{
    public interface IStoreService
    {
        IEnumerable<Product> GetProducts();
        IEnumerable<Product> SearchProducts(string searchTerm);
        Product GetProduct(int id);
        IEnumerable<StoreInfo> GetStores();
    }

    public class StoreService : IStoreService
    {
        // The catalogue holds ~50k rows but only product1..product9.png ship with the app,
        // so anything past the first nine renders a broken image.
        private const int MaxProducts = 9;
        private const int MaxStores = 15;

        private readonly Func<IStoreDbContext> _contextFactory;

        public StoreService(Func<IStoreDbContext> contextFactory)
        {
            _contextFactory = contextFactory ?? throw new ArgumentNullException(nameof(contextFactory));
        }

        public IEnumerable<Product> GetProducts()
        {
            using var context = _contextFactory();

            return context.Products
                .OrderBy(p => p.Id)
                .Take(MaxProducts)
                .ToList();
        }

        public IEnumerable<Product> SearchProducts(string searchTerm)
        {
            if (string.IsNullOrWhiteSpace(searchTerm))
            {
                return GetProducts();
            }

            var term = searchTerm.Trim();

            using var context = _contextFactory();

            return context.Products
                .Where(p => p.Name.Contains(term) || p.Description.Contains(term))
                .OrderBy(p => p.Name)
                .Take(MaxProducts)
                .ToList();
        }

        public Product GetProduct(int id)
        {
            using var context = _contextFactory();

            return context.Products.FirstOrDefault(p => p.Id == id);
        }

        public IEnumerable<StoreInfo> GetStores()
        {
            using var context = _contextFactory();

            return context.Stores
                .OrderBy(s => s.Id)
                .Take(MaxStores)
                .ToList();
        }
    }
}
