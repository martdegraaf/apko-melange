# Stage 1: Build
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0-noble-aot AS build
ARG TARGETARCH
WORKDIR /source

# Copy project file and restore
COPY src/WeatherApi/WeatherApi.csproj src/WeatherApi/
RUN dotnet restore src/WeatherApi/WeatherApi.csproj -a $TARGETARCH

# Copy source and publish with AOT
COPY src/WeatherApi/. src/WeatherApi/
RUN dotnet publish src/WeatherApi/WeatherApi.csproj \
    -a $TARGETARCH \
    --no-restore \
    -o /app

# Stage 2: Runtime (chiseled, non-root by default)
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-noble-chiseled
EXPOSE 8080
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["./WeatherApi"]
