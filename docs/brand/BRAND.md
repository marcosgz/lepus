# Lepus brand kit

## The mark

A capital L drawn as a single route. The upright is the hare's ear; the foot curls back into a rounded body, and the amber dot inside it is a message in transit. One line, one stop, one message: the mark reads as "L", as a hare, and as a route carrying work.

## Colours

| Role  | Light background | Dark background |
|-------|------------------|-----------------|
| Ink   | `#1a2233`        | `#e3e9f3`       |
| Amber | `#f2a30f`        | `#f2a30f`       |
| Tile (app icons) | `#1a2233` | `#1a2233` |

Amber is reserved for the message dot and the rule under "SAGA". Do not recolour the line in amber or put the dot in ink (except in the mono files).

## Clear space and minimum size

- Clear space: keep at least the height of the mark's body (the rounded loop, about one third of the mark's height) empty on every side.
- `mark*.svg`: 48 px and up.
- `mark-small*.svg` / `favicon.svg`: 16 to 48 px. Its line is heavier and every edge sits on the 16, 32, 48 and 64 px pixel grids, so it stays sharp at favicon sizes. Do not use it large.
- `lockup-lepus*`: 120 px wide minimum. `lockup-lepus-saga*`: 180 px wide minimum (below that, "SAGA" gets too small; use `lockup-lepus` or the mark alone).

## Which file where

| Use | File |
|-----|------|
| README header, Lepus | `lockup-lepus-on-light.svg` + `lockup-lepus-on-dark.svg` in a `<picture>` (below) |
| README header, Lepus saga | `lockup-lepus-saga-on-light.svg` + `lockup-lepus-saga-on-dark.svg` |
| Web page header that follows the OS theme | `lockup-lepus.svg`, `lockup-lepus-saga.svg`, `mark.svg` (ink switches with `prefers-color-scheme`) |
| Inline in an app that sets its own text colour | `*-mono.svg` (everything is `currentColor`) |
| Fixed background you control | `*-on-light.svg` / `*-on-dark.svg` |
| Browser tab | `favicon.svg` (adaptive), with `favicon.ico` (16/32/48) as fallback |
| iOS home screen | `apple-touch-icon.png` (180, solid tile) |
| Web manifest / PWA | `icon-512.png` (solid tile, mark inside the maskable safe zone) |
| Legacy PNG favicons | `favicon-16.png`, `favicon-32.png` (transparent, light-background ink) |

All wordmark text is outlined Overpass (SIL Open Font License), so no font is needed to render it.

### README

GitHub follows the viewer's GitHub theme only through `<picture>`, so use the light/dark pair rather than the adaptive file:

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/lockup-lepus-on-dark.svg">
    <img alt="Lepus" src="docs/brand/lockup-lepus-on-light.svg" width="278">
  </picture>
</p>
```

For Lepus saga, swap in `lockup-lepus-saga-on-dark.svg` / `lockup-lepus-saga-on-light.svg` and `width="359"`.

### HTML head

```html
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
```

## Don'ts

- Don't redraw the wordmark in live text or another typeface.
- Don't stretch, rotate, outline or add effects to the mark.
- Don't put the ink mark on mid-tone or busy backgrounds; use the tile or the mono file instead.
