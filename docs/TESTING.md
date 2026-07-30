# Testy

## Jednostkowe

Uruchamiane przez `xcodebuild test` — pokrywają m.in.:

- konwersje współrzędnych / Retina
- model dokumentu, undo, warstwy
- serializację `.screenforge`
- szablony nazw plików
- render prostokąta, strzałki, tekstu, blur, pixelate, solid redact
- historię SQLite
- konflikty skrótów
- detekcję wrażliwych danych

## Integracyjne

`ScreenForgeIntegrationTests` — ustawienia, uprawnienia, schowek.

## Smoke (manualny)

1. Ikona menu bar widoczna
2. Onboarding / uprawnienie Nagrywanie ekranu
3. ⌃⇧1 — wybór obszaru → edytor
4. Dodaj strzałkę, tekst PL, numer, pixelate, redact
5. ⌘↩ — kopiuj i zamknij
6. ⌃⌥1 — bezpośrednio do schowka
7. Ostatni obszar, okno, pełny ekran, opóźnienie
8. Zapisz PNG, historia, OCR
9. Restart — ustawienia zachowane
