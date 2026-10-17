# Halloween application UI validation, 10 October 2026

The seasonal theme covers application login, lobby tabs, settings and application
dialogs. It is scoped to these surfaces; authored place interfaces and 3D
SubViewports are excluded. Classic resources are preserved and the preference
switch restores the original local styles, textures and icons. The running
window icon is switched once per preference change through DisplayServer.

The final tab-entry fix applies the theme synchronously during lobby setup and
prepares the selected lazy page before TabContainer makes it visible. Controls
added to a visible page and visible style changes are styled immediately. Hidden
updates retain a 1.8 ms queue budget. No recurring scan of the entire lobby,
fullscreen blocking cover, blur or expensive particle system was introduced.

Games and Catalog have text-only header buttons. Other navigation uses solid
24 px orange silhouettes with integrated seasonal details: haunted home,
costume profile, ghost messages/groups, pumpkin avatar/bag and moon editorial
icon. Classic SVG assets remain unchanged. The banner opens the actual Halloween
catalog subtab via CatalogBuilder.open_halloween, rather than only selecting the
generic catalog. Event/Limited items carry the same green badge and white text
in Catalog, Avatar wardrobe, Inventory and profile wearing cards. Other items
are not marked Limited.

Validation:

- `tools/validate_seasonal_theme.gd`: initial theme before first frame, a 150-panel
  hidden subtree prepared before visibility, Games/Catalog icon removal, Limited
  color preservation, exact classic restoration, async updates and reparenting.
- `tools/validate_seasonal_tab_entry.gd`: real lobby lazy Avatar/Inventory/Catalog
  entries have no visible white panel before their first frame; banner selects
  Halloween directly; Inventory and Avatar event cards have Limited badges.
- `tools/validate_avatar_responsive_halloween.gd`: 480×800 portrait and 1280×720
  landscape, preview resolution/height bounds, scroll behavior, palette and
  wardrobe columns. The obsolete Mobile Beta banner is absent.
- `tools/validate_cached_lobby_shell.gd`: cached shell appears while background
  authentication is suspended, failed authentication retries inline, join error
  returns inline, and actual world-joining progress still works.
- `tools/validate_mobile_ui_scroll.gd`: real screen-touch swipe/tap separation,
  nested horizontal/vertical scrolling, clipped/hidden/modal hit tests, fractional
  scrolling and restoration of temporarily disabled buttons.
- `tools/validate_seasonal_ui.gd`: Windows GL rendering reviewed, classic and
  Halloween running-window icon checks and visual restoration passed. Latest
  screenshot is `.codex-tmp/halloween-theme/appdata/Godot/app_userdata/Bobux/validation/halloween/lobby.png`.

Headless contracts passed. Windows rendering produced no script errors; the
graphics fixture reports two generic ObjectDB objects at shutdown. These tests
do not stand in for the shipping APK touch/performance checks performed by the
release owner on the connected phone. No editor import, APK installation,
export, server modification or deployment was performed by the UI agent.
