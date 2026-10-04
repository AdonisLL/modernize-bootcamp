using System;
using System.Data.Entity;

using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using eShopLite.StoreFx.Data;
using eShopLite.StoreFx.Services;

namespace eShopLite.StoreFx
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);

            // The SQL schema scripts are the source of truth; EF must never alter the database.
            Database.SetInitializer<StoreDbContext>(null);

            var connectionString = builder.Configuration.GetConnectionString("StoreDbContext");

            builder.Services.AddControllersWithViews();
            builder.Services.AddHttpContextAccessor();

            builder.Services.AddDistributedMemoryCache();
            builder.Services.AddSession(options =>
            {
                options.IdleTimeout = TimeSpan.FromMinutes(30);
                options.Cookie.HttpOnly = true;
                options.Cookie.IsEssential = true;
            });

            builder.Services
                .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
                .AddCookie(options =>
                {
                    options.Cookie.Name = ".ESHOPLITEAUTH";
                    options.Cookie.HttpOnly = true;
                    options.LoginPath = "/Account/Login";
                    options.LogoutPath = "/Account/Logout";
                    options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
                    options.SlidingExpiration = true;
                });
            builder.Services.AddAuthorization();

            // One StoreDbContext per request, so every service in a request shares a single unit of work.
            builder.Services.AddScoped<IStoreDbContext>(_ => new StoreDbContext(connectionString));
            builder.Services.AddScoped<ISessionStore, HttpContextSessionStore>();
            builder.Services.AddScoped<IStoreService, StoreService>();
            builder.Services.AddScoped<IAuthService, AuthService>();
            builder.Services.AddScoped<ICartService, SessionCartService>();
            builder.Services.AddScoped<IOrderService, OrderService>();

            var app = builder.Build();

            if (app.Environment.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }
            else
            {
                app.UseExceptionHandler("/Home/Error");
            }

            app.UseStaticFiles();
            app.UseRouting();

            app.UseSession();
            app.UseAuthentication();
            app.UseAuthorization();

            app.MapControllerRoute(
                name: "default",
                pattern: "{controller=Home}/{action=Index}/{id?}");

            app.Run();
        }
    }
}
