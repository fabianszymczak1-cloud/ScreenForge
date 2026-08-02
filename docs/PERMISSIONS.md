# Uprawnienia

## Nagrywanie ekranu (wymagane)

Wymagane do wszystkich zrzutów przez ScreenCaptureKit.

Uruchamiaj **tylko** `/Applications/ScreenForge.app` (nie z zamontowanego DMG ani DerivedData).

### Jak nadać dostęp (właściwa ścieżka)

1. W ScreenForge: **Poproś o uprawnienie** → systemowy sheet (`CGRequestScreenCaptureAccess`).
2. Zatwierdź. macOS może zamknąć aplikację — otwórz ponownie → **Sprawdź ponownie**.

**Nie dodawaj appki przyciskiem „+” w Ustawieniach → Nagrywanie ekranu.** Na Tahoe to często nic nie robi. Settings służą najwyżej do włączenia **istniejącego** wiersza.

### Podpis release

Domyślnie ad-hoc (`codesign -`), jak PasteRush i ScreenForge 1.0.6–1.0.14, które potrafiły zarejestrować Screen Recording. Opcjonalnie `SCREENFORGE_SIGN_IDENTITY` (np. ScreenForge Release) — nie jest defaultem (1.0.15–1.0.16 pokazały problemy z TCC).

### Stary wiersz vs bieżąca binarka

`CGPreflightScreenCaptureAccess()` mówi prawdę dla **tej** binarki. Lista w Ustawieniach może pokazywać ScreenForge ze starego CDHash.

Ostateczność: **Wyczyść stare wpisy**, potem znowu **Poproś o uprawnienie** (nie „+”).

### Sprawdzanie w aplikacji

- **Check again** → `CGPreflight` (oraz SCK tylko gdy preflight już jest true).
- **Request permission** → `CGRequestScreenCaptureAccess` (bez natychmiastowego probe SCK).

## Dostępność (opcjonalne)

Potrzebne tylko dla:

- opcjonalnego auto-wklejania ⌘V po skopiowaniu,
- eksperymentalnego zrzutu przewijanego (gdy włączony).

## Launch at Login

Używa `SMAppService.mainApp` — użytkownik zatwierdza w ustawieniach logowania systemu.
