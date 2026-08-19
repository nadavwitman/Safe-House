# theme

## [colors.dart](colors.dart)

`AppColors`: the app's entire color palette as static constants — a warm cream/sage design system, not Material's default. Organized into background, surface (`card`/`card2`/`card3`, `line`/`line2`), ink (text, `ink900`→`ink300` darkest→lightest), sage (the primary brand color, `sage800`→`sage50`), and status (`ok`/`warn`/`alert`, each with a `*Soft` background variant for badges/banners).

`iconWellBg(tone)` / `iconWellFg(tone)` map a semantic tone string (`'sage'`, `'warm'`, `'coral'`, `'cream'`, `'sky'`, `'plum'`) to a background/foreground color pair, used throughout [widgets/shared_widgets.dart](../widgets/README.md)'s `IconWell` and by [screens/](../screens/README.md) to color-code sensor types (e.g. kitchen is `'warm'`, bathroom is `'sky'`, medication is `'plum'`) — the same tone strings appear scattered across the sensor definitions in the dashboard, alerts, and admin screens, all resolving through this one map.
