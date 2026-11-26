# API do GranaPaCá: build no SDK e runtime chiseled, sem shell e sem root (ADR-010).
# Multi-arch: docker buildx build --platform linux/amd64,linux/arm64 backend

# The publish is portable IL, so it runs once on the build machine's own architecture.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:11.0@sha256:2794448a07118a6eaf00f29ab5d2bf44928517ce5ff86505a63a69230374f599 AS build
WORKDIR /src
COPY Directory.Build.props Directory.Packages.props ./
COPY src/ src/
RUN dotnet restore src/GranaPaCa.Api --locked-mode \
 && dotnet publish src/GranaPaCa.Api --no-restore -c Release -o /app

# Only COPY below, so the arm64 image builds without emulation.
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra@sha256:c8dd08a50d8ffd19bd8da72edee05a7ac15b486a5b1869cf46fdb370bf1fbc76
WORKDIR /app
COPY --from=build /app .
# The chiseled image already runs as the non-root user "app" and listens on 8080.
USER $APP_UID
ENTRYPOINT ["dotnet", "GranaPaCa.Api.dll"]
