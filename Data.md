# Image Size Vergelijking

Gemeten op 2026-05-15 met .NET 10.0.8, `linux-x64` (amd64).

## Resultaten

| Image | Base OS | Size | Non-root | Shell beschikbaar |
|-------|---------|------|----------|-------------------|
| `weather-chiseled` | Ubuntu 24.04 Noble (chiseled) | **44.1 MB** | Ja | Nee |
| `weather-apko` | Wolfi | **48.1 MB** | Ja (uid 65532) | Nee |

## Runtime Info

| Property | Chiseled | apko/melange |
|----------|----------|--------------|
| Runtime | .NET 10.0.8 | .NET 10.0.8 |
| OS Description | Ubuntu 24.04.4 LTS | Wolfi |
| Architecture | X64 | X64 |
| Publish mode | Native AOT (self-contained) | Native AOT (self-contained) |

## Waarom `busybox` in melange.yaml?

Melange bouwt APK packages door pipeline-stappen uit te voeren in een chroot-omgeving (met `bubblewrap`). De `pipeline.runs` stap in `melange.yaml` is een shell-script:

```yaml
pipeline:
  - runs: |
      mkdir -p ${{targets.destdir}}/app
      cp -r /home/build/output/* ${{targets.destdir}}/app/
      chmod +x ${{targets.destdir}}/app/WeatherApi
```

Dit script vereist `/bin/sh` om uitgevoerd te worden. Het `wolfi-baselayout` package bevat **geen** shell — het levert alleen de basis directory-structuur (`/etc`, `/var`, etc.).

`busybox` levert:
- `/bin/sh` — de shell interpreter die melange nodig heeft om `runs:` stappen uit te voeren
- `mkdir`, `cp`, `chmod` — de standaard Unix-utilities die in het script worden gebruikt

**Belangrijk**: `busybox` is alleen nodig in de melange **build** environment (`environment.contents.packages`), niet in het uiteindelijke apko runtime image. Het runtime image (`apko.yaml`) bevat geen `busybox` of shell, wat het attack surface minimaliseert.

## SDK Image: waarom `-aot`?

Native AOT compilatie vereist een platform linker (`clang` of `gcc`). Het standaard SDK image `mcr.microsoft.com/dotnet/sdk:10.0-noble` bevat deze **niet**. De `-aot` variant (`sdk:10.0-noble-aot`) bevat:
- `clang` — de LLVM C/C++ compiler/linker
- `zlib` — compressie library
- Andere native toolchain dependencies

Zonder de `-aot` variant krijg je:
```
error : Platform linker ('clang' or 'gcc') not found in PATH.
```
