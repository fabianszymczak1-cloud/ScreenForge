# ScreenForge — raport końcowy

## Lokalizacje

| Element | Ścieżka |
|---------|---------|
| Kod źródłowy | `ScreenForge/` |
| Projekt Xcode | `ScreenForge.xcodeproj` |
| Gotowe `.app` | `/Applications/ScreenForge.app` |
| Release build | `ScreenForge/build/DerivedData/Build/Products/Release/ScreenForge.app` |

## Środowisko builda

- Deployment target: **macOS 26.0**
- Bundle ID: `com.local.ScreenForge`
- Podpis: ad-hoc
- Debug build: **SUCCEEDED**
- Release build: **SUCCEEDED**
- Testy jednostkowe: **24/24 PASSED**
- Smoke test (`--smoke-test`): **PASSED** (14/14)

## Smoke (z `/Applications`)

- Uprawnienie Nagrywanie ekranu: OK
- Przechwycenie aktywnego ekranu: 1512×982 w ~143 ms
- Edytor (prostokąt, strzałka, tekst PL, krok, pixelate, redact): OK
- Undo/redo, render, schowek, PNG, projekt `.screenforge`: OK
- Historia, OCR lokalny, ostatni region, crop, ustawienia: OK
- Przechwycenie okna: OK

## Benchmarki (syntetyczne)

| Operacja | 1920×1080 | 2560×1440 | 3840×2160 | Retina 3024×1964 |
|----------|-----------|-----------|-----------|------------------|
| crop | ~0 ms | ~0 ms | ~0 ms | ~0 ms |
| PNG encode | 15 ms | 22 ms | 41 ms | 27 ms |
| pixelate (downsample) | 0.1 ms | 0.1 ms | 0.3 ms | 0.2 ms |

## Domyślne skróty

- ⌃⇧1 — obszar → edytor
- ⌃⇧2 — okno → edytor
- ⌃⇧3 — aktywny ekran
- ⌃⇧4 — wszystkie ekrany
- ⌃⇧5 — ostatni obszar → edytor
- ⌃⇧6 — z opóźnieniem
- ⌃⇧7 — historia
- ⌃⇧8 — ostatni zrzut w edytorze
- ⌃⌥1 — obszar → schowek
- ⌃⌥2 — okno → schowek
- ⌃⌥3 — ekran → schowek
- ⌃⌥4 — ostatni obszar → schowek

## Ukończone funkcje

Menu bar, onboarding, ustawienia, ScreenCaptureKit + freeze overlay, wybór regionu z lupą, ostatni region, okno, pełny/wszystkie ekrany, opóźnienie, globalne skróty, routing, schowek, eksport, edytor obiektowy, efekty (blur/pixelate/redact/highlight/focus/magnify), crop, undo, `.screenforge`, historia SQLite, OCR Vision, detekcja wrażliwych danych, presety, launch at login, powiadomienia lokalne.

## Eksperymentalne

- Zrzut przewijany — flaga w Ustawieniach → Zaawansowane

## Zależności zewnętrzne

Brak — wyłącznie frameworki Apple.

## Znane ograniczenia

Zobacz `docs/LIMITATIONS.md`.

## Uruchomienie (3 kroki)

1. Otwórz `/Applications/ScreenForge.app`
2. Upewnij się, że **Nagrywanie ekranu** jest włączone dla ScreenForge
3. Użyj `⌃⇧1` (edytor) lub `⌃⌥1` (schowek)
