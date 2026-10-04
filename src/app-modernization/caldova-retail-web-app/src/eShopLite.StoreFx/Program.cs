using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Security.Claims;
using System.Threading.Tasks;

using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using eShopLite.StoreFx.Components;
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

            builder.Services.AddRazorComponents()
                .AddInteractiveServerComponents();

            builder.Services.AddCascadingAuthenticationState();
            builder.Services.AddHttpContextAccessor();

            builder.Services
                .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
                .AddCookie(options =>
                {
                    options.Cookie.Name = ".ESHOPLITEAUTH";
                    options.Cookie.HttpOnly = true;
                    options.LoginPath = "/account/login";
                    options.LogoutPath = "/account/logout";
                    options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
                    options.SlidingExpiration = true;
                });
            builder.Services.AddAuthorization();

            // A fresh, short-lived EF6 context per operation keeps circuits from holding a
            // long-lived DbContext.
            builder.Services.AddScoped<Func<IStoreDbContext>>(_ => () => new StoreDbContext(connectionString));
            builder.Services.AddScoped<IStoreService, StoreService>();
            builder.Services.AddScoped<IAuthService, AuthService>();
            builder.Services.AddScoped<IOrderService, OrderService>();

            // Circuit-scoped cart, persisted in encrypted browser session storage.
            builder.Services.AddScoped<CartState>();

            var app = builder.Build();

            if (!app.Environment.IsDevelopment())
            {
                app.UseExceptionHandler("/error", createScopeForErrors: true);
            }

            app.UseStaticFiles();
            app.UseAntiforgery();

            app.UseAuthentication();
            app.UseAuthorization();

            MapAuthEndpoints(app);

            app.MapRazorComponents<App>()
                .AddInteractiveServerRenderMode();

            app.Run();
        }

        // Cookie sign-in/out must run on the HTTP response, so they live in endpoints rather
        // than Blazor circuits. Login validates the antiforgery token; logout opts out (the
        // worst a logout CSRF can do is sign a user out).
        private static void MapAuthEndpoints(WebApplication app)
        {
            app.MapPost("/account/login", async (HttpContext http, IAuthService authService, IAntiforgery antiforgery) =>
            {
                try
                {
                    await antiforgery.ValidateRequestAsync(http);
                }
                catch
                {
                    return Results.Redirect("/account/login?error=1");
                }

                var form = await http.Request.ReadFormAsync();
                var userName = form["userName"].ToString();
                var password = form["password"].ToString();
                var rememberMe = form["rememberMe"].ToString().Contains("true", StringComparison.OrdinalIgnoreCase)
                                 || form["rememberMe"].ToString().Contains("on", StringComparison.OrdinalIgnoreCase);
                var returnUrl = form["returnUrl"].ToString();

                var user = authService.ValidateUser(userName, password);
                if (user == null)
                {
                    var back = "/account/login?error=1";
                    if (!string.IsNullOrEmpty(returnUrl))
                    {
                        back += "&returnUrl=" + Uri.EscapeDataString(returnUrl);
                    }

                    return Results.Redirect(back);
                }

                var claims = new List<Claim> { new Claim(ClaimTypes.Name, user.UserName) };
                foreach (var role in (user.Roles ?? string.Empty)
                             .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    claims.Add(new Claim(ClaimTypes.Role, role));
                }

                var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
                var properties = new AuthenticationProperties
                {
                    IsPersistent = rememberMe,
                    ExpiresUtc = DateTimeOffset.UtcNow.AddMinutes(30)
                };

                await http.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, new ClaimsPrincipal(identity), properties);

                var destination = !string.IsNullOrEmpty(returnUrl) && Uri.IsWellFormedUriString(returnUrl, UriKind.Relative)
                    ? returnUrl
                    : "/";

                return Results.Redirect(destination);
            }).DisableAntiforgery();

            app.MapPost("/account/logout", async (HttpContext http) =>
            {
                await http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
                return Results.Redirect("/");
            }).DisableAntiforgery();
        }
    }
}
