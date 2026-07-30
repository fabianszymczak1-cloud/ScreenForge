# Znane ograniczenia

- Zrzut przewijany jest eksperymentalny i ukryty za flagą w ustawieniach Zaawansowane.
- Auto-wklejanie ⌘V wymaga opcjonalnego uprawnienia Dostępność.
- Rozpoznawanie okien zależy od API ScreenCaptureKit (bez prywatnych hacków AX poza opcjonalnymi funkcjami).
- Blur i pixelate nie gwarantują nieodwracalnego ukrycia danych — używaj Solid redact.
- HEIC zależy od stabilności ImageIO na danym systemie.
- Pełna automatyzacja smoke (globalne skróty + Screen Recording) wymaga interakcji użytkownika z TCC.
