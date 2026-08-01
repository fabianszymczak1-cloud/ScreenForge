# Uprawnienia

## Nagrywanie ekranu (wymagane)

Wymagane do wszystkich zrzutów przez ScreenCaptureKit.

Ustawienia systemowe → Prywatność i ochrona → Nagrywanie ekranu → włącz ScreenForge.

Uruchamiaj **tylko** `/Applications/ScreenForge.app` (nie z zamontowanego DMG ani DerivedData).

### Stary wiersz w Ustawieniach vs bieżąca binarka

`CGPreflightScreenCaptureAccess()` mówi prawdę dla **tej** binarki. Lista w Ustawieniach
może nadal pokazywać ScreenForge z poprzedniego ad-hoc CDHash / ścieżki pod tą samą nazwą.

Release’y od 1.0.15 podpisuje lokalny certyfikat **ScreenForge Release** (stabilne DR).
Po aktualizacji ze starszego ad-hoc builda: w onboardingu **Wyczyść stare wpisy
Nagrywania ekranu**, potem **Poproś o uprawnienie** raz z `/Applications`.

### Sprawdzanie w aplikacji

- **Check again** → `CGPreflight` (oraz SCK tylko gdy preflight już jest true).
- **Request permission** → `CGRequestScreenCaptureAccess` (bez natychmiastowego probe SCK).
- Nie wywołujemy `SCShareableContent` przy każdym otwarciu onboardingu gdy dostępu brak —
  to ponownie odpala systemowy sheet i myli diagnostykę.

## Dostępność (opcjonalne)

Potrzebne tylko dla:

- opcjonalnego auto-wklejania ⌘V po skopiowaniu,
- eksperymentalnego zrzutu przewijanego (gdy włączony).

## Launch at Login

Używa `SMAppService.mainApp` — użytkownik zatwierdza w ustawieniach logowania systemu.
