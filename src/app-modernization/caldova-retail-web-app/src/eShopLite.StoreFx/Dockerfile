# Build context is the solution root (caldova-retail-web-app). Build with:
#   docker build --file src/eShopLite.StoreFx/Dockerfile --tag caldova-retail:local .

# --- Restore + publish (SDK image, build stage only) ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /source

# Restore as a separate layer so it is cached until the project file changes.
COPY src/eShopLite.StoreFx/eShopLite.StoreFx.csproj src/eShopLite.StoreFx/
RUN dotnet restore src/eShopLite.StoreFx/eShopLite.StoreFx.csproj

COPY . .
RUN dotnet publish src/eShopLite.StoreFx/eShopLite.StoreFx.csproj \
    --configuration Release \
    --no-restore \
    --output /app

# --- Runtime (smaller ASP.NET image, final stage) ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /app .

# Bind Kestrel to the port the Container Apps ingress targets (targetPort: 8080).
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

# Run as the non-root user that the base image provides instead of root.
USER $APP_UID

ENTRYPOINT ["dotnet", "eShopLite.StoreFx.dll"]
