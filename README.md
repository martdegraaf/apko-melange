# .NET 10 Container Vergelijking: Chiseled vs apko/melange

Vergelijking van twee benaderingen voor het bouwen van minimale, veilige container images voor .NET 10 applicaties.

## Projecten

Beide projecten gebruiken dezelfde **WeatherApi** — een .NET 10 minimal API gepubliceerd met **Native AOT**.

### 1. Chiseled (Microsoft)

Multi-stage Dockerfile met `runtime-deps:10.0-noble-chiseled` als runtime base.

```bash
docker build -t weather-chiseled -f chiseled/Dockerfile .
docker run -p 8081:8080 weather-chiseled
```

### 2. apko/melange (Chainguard)

De app wordt verpakt als APK package (melange) en geassembleerd tot een OCI image met Wolfi packages (apko).

```bash
cd apko && ./build.sh
docker run -p 8082:8080 weather-apko:latest
```

## Test

```bash
curl http://localhost:8081/weatherforecast
curl http://localhost:8082/weatherforecast
```

## Presentatie

Zie [GUIDE.md](GUIDE.md) voor een volledige walkthrough inclusief image size vergelijking en security scanning.

## Structuur

```
├── src/WeatherApi/        # .NET 10 AOT minimal API
├── chiseled/Dockerfile    # Microsoft chiseled image build
├── apko/
│   ├── melange.yaml       # APK package definitie
│   ├── apko.yaml          # OCI image assembly
│   └── build.sh           # Build orchestratie
├── GUIDE.md               # Presentatie guide
└── README.md
```
