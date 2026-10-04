using System;
using System.Threading.Tasks;

using Microsoft.AspNetCore.Components.Server.ProtectedBrowserStorage;

using eShopLite.StoreFx.Models;

namespace eShopLite.StoreFx.Services
{
    /// <summary>
    /// Replaces the old ISession-based cart. State lives for the Blazor circuit and is
    /// persisted to encrypted browser session storage, so the cart survives a full-page
    /// navigation (including signing in) just like the original server session did.
    /// </summary>
    public class CartState
    {
        public const string StorageKey = "eShopLite.Cart";

        private readonly ProtectedSessionStorage _storage;
        private Cart _cart = new Cart();

        public CartState(ProtectedSessionStorage storage)
        {
            _storage = storage ?? throw new ArgumentNullException(nameof(storage));
        }

        public Cart Cart => _cart;

        public bool Loaded { get; private set; }

        /// <summary>Raised after the cart changes so the nav badge and pages can refresh.</summary>
        public event Action OnChange;

        /// <summary>
        /// Loads the cart from browser storage. Safe to call repeatedly; the first successful
        /// load wins. Must run after the component is interactive (JS interop available).
        /// </summary>
        public async Task EnsureLoadedAsync()
        {
            if (Loaded)
            {
                return;
            }

            try
            {
                var result = await _storage.GetAsync<Cart>(StorageKey);
                _cart = result.Success && result.Value != null ? result.Value : new Cart();
            }
            catch
            {
                // No interactivity yet or unreadable payload - start from an empty cart.
                _cart = new Cart();
            }

            Loaded = true;
            NotifyChanged();
        }

        public async Task AddAsync(Product product, int quantity)
        {
            _cart.Add(product, quantity);
            await SaveAsync();
        }

        public async Task SetQuantityAsync(int productId, int quantity)
        {
            _cart.SetQuantity(productId, quantity);
            await SaveAsync();
        }

        public async Task RemoveAsync(int productId)
        {
            _cart.Remove(productId);
            await SaveAsync();
        }

        public async Task ClearAsync()
        {
            _cart.Clear();
            await SaveAsync();
        }

        private async Task SaveAsync()
        {
            await _storage.SetAsync(StorageKey, _cart);
            Loaded = true;
            NotifyChanged();
        }

        private void NotifyChanged() => OnChange?.Invoke();
    }
}
