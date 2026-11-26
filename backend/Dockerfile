# API do GranaPaCá: build no SDK e runtime chiseled, sem shell e sem root (ADR-010).
# Multi-arch: docker buildx build --platform linux/amd64,linux/arm64 backend

# The publish is portable IL, so it runs once on the build machine's own architecture.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0@sha256:8c6edfb26c85153f236d26efebd9ad349aec403583f343f201ee67838b23658d AS build
WORKDIR /src
COPY Directory.Build.props Directory.Packages.props ./
COPY src/ src/
RUN dotnet restore src/GranaPaCa.Api --locked-mode \
 && dotnet publish src/GranaPaCa.Api --no-restore -c Release -o /app \
 && mkdir -p /appdata

# Only COPY below, so the arm64 image builds without emulation.
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra@sha256:c8dd08a50d8ffd19bd8da72edee05a7ac15b486a5b1869cf46fdb370bf1fbc76
WORKDIR /app
COPY --from=build /app .
COPY --from=build --chown=$APP_UID:$APP_UID /appdata /var/lib/granapaca/files
# The chiseled image already runs as the non-root user "app" and listens on 8080.
USER $APP_UID
ENTRYPOINT ["dotnet", "GranaPaCa.Api.dll"]
