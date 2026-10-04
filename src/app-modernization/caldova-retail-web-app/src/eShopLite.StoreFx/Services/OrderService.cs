using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Linq;

using eShopLite.StoreFx.Data;
using eShopLite.StoreFx.Models;

namespace eShopLite.StoreFx.Services
{
    public interface IOrderService
    {
        Order PlaceOrder(Cart cart, string userName);
        Order GetOrder(int id, string userName);
        IEnumerable<Order> GetOrdersForUser(string userName);
        OrderSummary GetSummary(string userName);
    }

    public class OrderService : IOrderService
    {
        // Orders are stored against a store, but the cart has no store concept yet, so every
        // line is booked to the first store until the UI lets the customer choose one.
        private const int DefaultStoreId = 1;

        private readonly Func<IStoreDbContext> _contextFactory;

        public OrderService(Func<IStoreDbContext> contextFactory)
        {
            _contextFactory = contextFactory ?? throw new ArgumentNullException(nameof(contextFactory));
        }

        // The app identifies users by name everywhere; the orders table keys off the user id.
        // Returns 0 (never a real id) when the name is unknown, so callers just find nothing.
        private static int ResolveUserId(IStoreDbContext context, string userName)
        {
            if (string.IsNullOrWhiteSpace(userName)) return 0;

            return context.Users
                .Where(u => u.UserName == userName)
                .Select(u => u.Id)
                .FirstOrDefault();
        }

        public Order PlaceOrder(Cart cart, string userName)
        {
            if (cart == null) throw new ArgumentNullException(nameof(cart));
            if (string.IsNullOrWhiteSpace(userName)) throw new ArgumentException("User name is required.", nameof(userName));
            if (cart.IsEmpty) throw new InvalidOperationException("Cannot place an order for an empty cart.");

            using var context = _contextFactory();

            var userId = ResolveUserId(context, userName);
            if (userId == 0) throw new InvalidOperationException("Unknown user '" + userName + "'.");

            var order = new Order
            {
                UserId = userId,
                PlacedUtc = DateTime.UtcNow,
                Total = cart.Total
            };

            foreach (var item in cart.Items)
            {
                order.Lines.Add(new OrderLine
                {
                    StoreId = DefaultStoreId,
                    ProductId = item.ProductId,
                    ProductName = item.Name,
                    UnitPrice = item.UnitPrice,
                    Quantity = item.Quantity
                });
            }

            context.Orders.Add(order);
            context.SaveChanges();

            return order;
        }

        public Order GetOrder(int id, string userName)
        {
            using var context = _contextFactory();

            var userId = ResolveUserId(context, userName);

            return context.Orders
                .Include(o => o.Lines)
                .FirstOrDefault(o => o.Id == id && o.UserId == userId);
        }

        public IEnumerable<Order> GetOrdersForUser(string userName)
        {
            using var context = _contextFactory();

            var userId = ResolveUserId(context, userName);

            return context.Orders
                .Include(o => o.Lines)
                .Where(o => o.UserId == userId)
                .OrderByDescending(o => o.PlacedUtc)
                .ToList();
        }

        public OrderSummary GetSummary(string userName)
        {
            using var context = _contextFactory();

            return context.GetOrderSummary(ResolveUserId(context, userName));
        }
    }
}
