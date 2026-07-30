# Architektura ScreenForge

## Warstwy

- **App** — `ScreenForgeApp`, `AppDelegate`, `AppLifecycleController`, `AppServices` (DI kontener)
- **Capture** — ScreenCaptureKit, freeze overlay, wybór regionu/okna, ostatni region, opóźnienie
- **Core** — współrzędne Retina, topologia monitorów, hotkeys, uprawnienia, diagnostyka
- **Editor** — model dokumentu, renderer, canvas AppKit, undo, presety
- **Export** — schowek, pliki, Share, format `.screenforge`
- **History** — SQLite + pliki w Application Support
- **OCR** — Vision (lokalnie), detekcja wrażliwych danych
- **UI** — menu bar, onboarding, ustawienia SwiftUI, historia, powiadomienia

## Przepływ zrzutu obszaru

1. Globalny hotkey → `AppServices.handleHotkey`
2. `RegionSelectionCoordinator` zamraża ekrany przez ScreenCaptureKit
3. Overlay na każdym monitorze z lupą i wymiarami
4. Po zatwierdzeniu wycinek z zamrożonej klatki
5. `CaptureResultRouter` kieruje do edytora / schowka / zapisu / historii

## Współrzędne

`CoordinateConverter` przelicza AppKit points ↔ piksele obrazu (top-left) z uwzględnieniem skali Retina i ujemnych originów monitorów.
