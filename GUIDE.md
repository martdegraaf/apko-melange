# Presentatie Guide: Chiseled vs apko/melange

Twee manieren om dezelfde .NET 10 AOT API te containerizen — vergeleken op image size, security en developer experience.

---

## Prerequisites

### Container Engine (kies één)

| Engine | Installatie | Opmerking |
|--------|-------------|-----------|
| Docker Desktop | [docker.com](https://www.docker.com/products/docker-desktop/) | Meest gebruikt, GUI beschikbaar |
| Podman Desktop | [podman-desktop.io](https://podman-desktop.io/) | Open-source, daemonless, rootless |

> Op Windows vereisen beide **WSL2** voor Linux containers. melange en apko zijn Linux tools die als containers draaien.

### Overige tools

| Tool | Installatie | Nodig voor |
|------|-------------|------------|
| .NET 10 SDK | [dot.net](https://dot.net/download) | Lokaal testen (optioneel) |
| grype | Zie onder | Security scanning |

**grype installeren:**

```bash
# Linux / macOS / WSL
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
```

```powershell
# Windows (scoop)
scoop install grype
```

> **melange** en **apko** draaien als containers — geen lokale installatie nodig. De scripts detecteren automatisch of je Docker of Podman gebruikt.

---

## Stap 1: Bouw de Chiseled Image

### Linux / macOS

```bash
# Vanuit de repo root (docker):
docker build -t weather-chiseled -f chiseled/Dockerfile .

# Of met podman:
podman build -t weather-chiseled -f chiseled/Dockerfile .
```

### Windows (PowerShell)

```powershell
# Vanuit de repo root (docker):
docker build -t weather-chiseled -f chiseled/Dockerfile .

# Of met podman:
podman build -t weather-chiseled -f chiseled/Dockerfile .
```

Dit gebruikt een multi-stage build:
- **Build stage**: `mcr.microsoft.com/dotnet/sdk:10.0-noble-aot` — compileert de app met Native AOT (de `-aot` variant bevat `clang` en andere AOT-vereisten)
- **Runtime stage**: `mcr.microsoft.com/dotnet/runtime-deps:10.0-noble-chiseled` — alleen OS dependencies, geen .NET runtime, geen shell, non-root by default

> **Let op**: De standaard `sdk:10.0-noble` image bevat **geen** `clang` linker. Native AOT vereist de `-aot` variant van het SDK image.

> **`.dockerignore`**: Zorg dat `**/bin/` en `**/obj/` in je `.dockerignore` staan. Zonder dit worden lokale Windows-specifieke NuGet cache paden (`project.assets.json`) mee gekopieerd naar de Linux build container, wat resulteert in `Unable to find fallback package folder` fouten.

---

## Stap 2: Bouw de apko/melange Image

### Linux / macOS

```bash
cd apko
chmod +x build.sh

# Auto-detect engine (podman als beschikbaar, anders docker):
./build.sh

# Of expliciet kiezen:
./build.sh docker
./build.sh podman
```

### Windows (PowerShell)

```powershell
cd apko

# Auto-detect engine:
.\build.ps1

# Of expliciet kiezen:
.\build.ps1 -Engine docker
.\build.ps1 -Engine podman
```

Het `build.sh` / `build.ps1` script doet 4 dingen:
1. **dotnet publish** in een `sdk:10.0-noble-aot` container → native AOT binary
2. **melange keygen** → genereer signing key (eenmalig)
3. **melange build** → verpak de binary als APK package (vereist `busybox` in `melange.yaml` voor `/bin/sh`)
4. **apko build** → assembleer een minimale OCI image met Wolfi packages + app APK

> **Waarom `busybox` in melange.yaml?** Melange voert de `pipeline.runs` stappen uit in een chroot. De `runs:` stap is een shell-script dat `/bin/sh` nodig heeft. Het `wolfi-baselayout` package bevat geen shell — `busybox` levert `/bin/sh` en standaard Unix-utilities (`cp`, `mkdir`, `chmod`) die nodig zijn om de pipeline uit te voeren. `busybox` is alleen nodig in de **build** environment, niet in het uiteindelijke runtime image.

> **Windows PowerShell tip**: Het `build.ps1` script gebruikt `$ErrorActionPreference = 'Continue'` omdat Docker, melange en apko info-logging naar stderr schrijven. Met `'Stop'` zou PowerShell deze meldingen als fatale fouten behandelen.

---

## Stap 3: Run beide containers

> Vervang `docker` door `podman` als je Podman gebruikt. De commando's zijn identiek.

```bash
# Terminal 1 — Chiseled
docker run -d --name chiseled -p 8081:8080 weather-chiseled

# Terminal 2 — apko/melange
docker run -d --name apko -p 8082:8080 weather-apko:latest
```

Test de endpoints:

```bash
# App info (toont runtime, OS, architectuur)
curl http://localhost:8081/
curl http://localhost:8082/
```

```powershell
# Windows PowerShell alternatief voor curl:
Invoke-RestMethod http://localhost:8081/
Invoke-RestMethod http://localhost:8082/
```

```bash
# Weather data
curl http://localhost:8081/weatherforecast
curl http://localhost:8082/weatherforecast
```

```powershell
# Windows PowerShell:
Invoke-RestMethod http://localhost:8081/weatherforecast
Invoke-RestMethod http://localhost:8082/weatherforecast
```

---

## Stap 4: Vergelijk Image Sizes

```bash
docker images | grep weather
# of
podman images | grep weather
```

Verwachte output (bij benadering):

| Image | Gemeten Size |
|-------|-------------|
| `weather-chiseled` | ~44 MB |
| `weather-apko` | ~48 MB |

> Zie [Data.md](Data.md) voor gedetailleerde metingen.

> Beide zijn klein door AOT (self-contained binary, geen .NET runtime). Het verschil zit in de base OS layer.

---

## Stap 5: Security Scanning

### Met grype

```bash
grype weather-chiseled
grype weather-apko:latest
```

### Met trivy (alternatief)

```bash
trivy image weather-chiseled
trivy image weather-apko:latest
```

Vergelijk:
- Aantal CVEs (Critical / High / Medium / Low)
- Welke packages CVEs bevatten
- Hoe snel patches beschikbaar zijn

---

## Stap 6: Inspecteer de images

```bash
# Bekijk layers
docker history weather-chiseled
docker history weather-apko:latest

# Bekijk image metadata
docker inspect weather-chiseled | jq '.[0].Config'
docker inspect weather-apko:latest | jq '.[0].Config'

# Probeer een shell te starten (moet falen bij chiseled!)
docker exec -it chiseled /bin/sh
docker exec -it apko /bin/sh
```

---

## Cleanup

```bash
docker rm -f chiseled apko
docker rmi weather-chiseled weather-apko:latest
```

```powershell
# Podman:
podman rm -f chiseled apko
podman rmi weather-chiseled weather-apko:latest
```

---

## Podman-specifieke Tips

### Rootless mode

Podman draait standaard rootless. melange heeft `--privileged` nodig voor de chroot-based build. Als dit problemen geeft:

```bash
# Podman met --privileged in rootless mode:
podman machine set --rootful
podman machine stop && podman machine start
```

### Podman op Windows

Podman op Windows draait via een Linux VM (Podman Machine). Zorg dat deze draait:

```powershell
podman machine init   # eenmalig
podman machine start
podman info           # verifieer dat het werkt
```

### Docker-compatibility

Podman is CLI-compatible met Docker. Je kunt een alias instellen:

```bash
# Linux/macOS
alias docker=podman
```

```powershell
# Windows PowerShell
Set-Alias -Name docker -Value podman
```

---

## Talking Points voor de Presentatie

### Microsoft Chiseled Images

| Pro | Con |
|-----|-----|
| Officieel door Microsoft onderhouden | Alleen Ubuntu-gebaseerd |
| Eenvoudige Dockerfile, vertrouwd voor .NET devs | Minder controle over wat er in de image zit |
| Automatische security patches via base image updates | Gebonden aan Microsoft's release cadence |
| Geïntegreerd in .NET tooling (`dotnet publish --os linux`) | Geen shell = lastig debuggen in productie |

### Chainguard apko/melange

| Pro | Con |
|-----|-----|
| Volledige controle over elke package in de image | Steilere leercurve |
| Wolfi packages met snelle CVE-patching (vaak < 24 uur) | Extra tooling nodig (melange, apko) |
| SBOM automatisch gegenereerd | Minder .NET-specifieke documentatie |
| Reproduceerbare builds (declaratief) | Complexer build process |
| Onafhankelijk van distro-vendor (niet gebonden aan Ubuntu/Microsoft) | Community kleiner dan Docker ecosystem |

### Wanneer welke kiezen?

- **Chiseled** → als je al in het Microsoft ecosystem zit, snelle setup wil, en vertrouwt op Microsoft voor security patches
- **apko/melange** → als je maximale controle wil, de snelste CVE-patching nodig hebt, of een supply chain security strategie bouwt met SBOMs en signed packages

---

## Architectuur Diagram

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│        CHISELED APPROACH        │    │     APKO/MELANGE APPROACH       │
├─────────────────────────────────┤    ├─────────────────────────────────┤
│                                 │    │                                 │
│  Dockerfile (multi-stage)       │    │  build.sh / build.ps1           │
│  ┌───────────────────────┐      │    │  ┌───────────────────────┐      │
│  │ sdk:10.0-noble        │      │    │  │ sdk:10.0-noble        │      │
│  │ dotnet publish (AOT)  │      │    │  │ dotnet publish (AOT)  │      │
│  └──────────┬────────────┘      │    │  └──────────┬────────────┘      │
│             │ binary            │    │             │ binary            │
│  ┌──────────▼────────────┐      │    │  ┌──────────▼────────────┐      │
│  │ runtime-deps:10.0     │      │    │  │ melange build         │      │
│  │ -noble-chiseled       │      │    │  │ → APK package         │      │
│  │ (Ubuntu 24.04 slim)   │      │    │  └──────────┬────────────┘      │
│  └──────────┬────────────┘      │    │             │ .apk              │
│             │                   │    │  ┌──────────▼────────────┐      │
│             ▼                   │    │  │ apko build            │      │
│     OCI Container Image        │    │  │ Wolfi packages + app  │      │
│                                 │    │  └──────────┬────────────┘      │
│                                 │    │             │                   │
│                                 │    │             ▼                   │
│                                 │    │     OCI Container Image        │
└─────────────────────────────────┘    └─────────────────────────────────┘
```
