import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Apple-style floating dock. Mounted at startup (kind: "panel",
// keepLoaded: true) and stays visible permanently — there is no
// open/close cycle like OSD or the menu, it just sits at the bottom of
// the screen.
//
// Pinned apps live in pinned.json next to this file (hand-edited, see
// README.md), not in shell.json — a list of up to 20 desktop-entry IDs is
// awkward to carry as bar-style inline settings, and a dedicated file is
// easier to hand-edit / diff / back up.
Item {
  id: root

  // Injected by omarchy-shell when this panel plugin is mounted.
  property var shell: null
  property string omarchyPath: ""

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  // ------------------------------------------------------------ pinned apps

  readonly property string pinnedPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/dino.dock/pinned.json"
  readonly property int maxPinned: 20

  property var pinnedIds: []    // ordered list of desktop-entry ids
  property var entryIndex: ({}) // desktop-entry id -> DesktopEntries entry object

  function loadPinned(rawText) {
    var text = String(rawText || "").trim()
    var ids = []
    if (text.length > 0) {
      try {
        var parsed = JSON.parse(text)
        if (Array.isArray(parsed)) {
          for (var i = 0; i < parsed.length; i++) {
            var id = String(parsed[i] || "").trim()
            if (id.length > 0) ids.push(id)
          }
        }
      } catch (e) {
        console.warn("dino.dock: pinned.json parse failed:", e)
      }
    }
    if (ids.length > root.maxPinned) {
      console.warn("dino.dock: " + ids.length + " pinned apps configured, showing the first " + root.maxPinned)
      ids = ids.slice(0, root.maxPinned)
    }
    root.pinnedIds = ids
  }

  FileView {
    id: pinnedFile
    path: root.pinnedPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPinned(text())
    onFileChanged: reload()
    onLoadFailed: root.loadPinned("")
  }

  function rebuildEntryIndex() {
    var idx = {}
    var values = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications) ? DesktopEntries.applications.values : []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (e && e.id) idx[String(e.id)] = e
    }
    root.entryIndex = idx
  }

  Connections {
    target: (typeof DesktopEntries !== "undefined") ? DesktopEntries.applications : null
    function onValuesChanged() { root.rebuildEntryIndex() }
  }

  // {id, entry, name, icon} per pinned slot, resolved against whatever
  // desktop entries currently exist. An id with no matching entry still
  // renders (fallback icon, id as its label) rather than silently vanishing,
  // so a typo in pinned.json is visible instead of just missing.
  readonly property var resolvedPins: {
    var out = []
    for (var i = 0; i < root.pinnedIds.length; i++) {
      var id = root.pinnedIds[i]
      var entry = root.entryIndex[id] || null
      out.push({
        id: id,
        entry: entry,
        name: entry ? String(entry.name || id) : id,
        icon: entry ? entry.icon : id
      })
    }
    return out
  }

  // ------------------------------------------------------------ running apps

  // Lowercased Wayland app_id -> toplevel. Heuristic matching (see README):
  // Wayland gives no reliable app_id <-> .desktop-id mapping, so this is a
  // best-effort dot, not a guarantee.
  property var runningAppIds: ({})

  function rebuildRunning() {
    var map = {}
    try {
      var values = ToplevelManager.toplevels.values
      for (var i = 0; i < values.length; i++) {
        var t = values[i]
        var key = String((t && t.appId) || "").toLowerCase()
        if (key.length > 0 && !map[key]) map[key] = t
      }
    } catch (e) {}
    root.runningAppIds = map
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuildRunning() }
  }

  function toplevelFor(pin) {
    var needle1 = String(pin.id || "").toLowerCase()
    var needle2 = pin.name ? String(pin.name).toLowerCase() : ""
    for (var key in root.runningAppIds) {
      if (key === needle1) return root.runningAppIds[key]
      if (needle1.length > 0 && (key.indexOf(needle1) !== -1 || needle1.indexOf(key) !== -1)) return root.runningAppIds[key]
      if (needle2.length > 0 && key.indexOf(needle2) !== -1) return root.runningAppIds[key]
    }
    return null
  }

  function launchOrFocus(pin, toplevel) {
    if (toplevel && typeof toplevel.activate === "function") {
      toplevel.activate()
    } else if (root.appLibrary) {
      root.appLibrary.launch(pin.id, pin.name)
    }
  }

  Component.onCompleted: {
    root.rebuildEntryIndex()
    root.rebuildRunning()
    if (root.appLibrary) root.appLibrary.refreshIcons()
  }

  // ------------------------------------------------------------ target monitor

  // Optional: pin the dock to one specific monitor instead of whichever
  // screen Quickshell enumerates first. Useful on multi-monitor rigs where
  // a docking station renumbers connector names (DP-5 vs DP-6) across
  // reboots — matching by manufacturer/model substring survives that,
  // matching by connector name alone doesn't.
  //
  // Config in monitor.json next to this file, a single JSON string with
  // any substring of the target's manufacturer/model/connector name,
  // case-insensitive (e.g. "Odyssey G50F", or just "DP-2"). Absent or
  // empty file = no preference, use the first enumerated screen.
  readonly property string monitorPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/dino.dock/monitor.json"
  property string monitorMatch: ""

  function loadMonitorMatch(rawText) {
    var text = String(rawText || "").trim()
    if (text.length === 0) { root.monitorMatch = ""; return }
    try {
      var parsed = JSON.parse(text)
      root.monitorMatch = String(parsed || "").trim().toLowerCase()
    } catch (e) {
      // Forgive a plain unquoted string too — less to get wrong by hand.
      root.monitorMatch = text.toLowerCase()
    }
  }

  FileView {
    id: monitorFile
    path: root.monitorPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadMonitorMatch(text())
    onFileChanged: reload()
    onLoadFailed: root.loadMonitorMatch("")
  }

  function screenMatches(screen) {
    if (!screen || root.monitorMatch.length === 0) return false
    var haystack = (String(screen.manufacturer || "") + " " + String(screen.model || "") + " " + String(screen.name || "")).toLowerCase()
    return haystack.indexOf(root.monitorMatch) !== -1
  }

  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (root.screenMatches(screens[i])) return screens[i]
    }
    // No match configured, or the configured monitor isn't plugged in
    // right now — fall back to something rather than rendering nowhere.
    return screens.length > 0 ? screens[0] : null
  }

  // ------------------------------------------------------------ the dock UI

  PanelWindow {
    id: panel
    visible: true
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Only the dock card (see below) accepts input; the rest of this
    // full-screen surface stays click-through so it never blocks the
    // desktop underneath, exactly like the notifications/OSD overlays.
    mask: Region { item: dockCard }

    readonly property real screenWidth: panel.screen ? panel.screen.width : 1920

    Item {
      id: dockCard
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.max(Style.space(10), Style.gapsOut)
      width: cardWidth
      height: cardHeight + headroom

      readonly property int maxIconSize: Style.space(50)
      readonly property int minIconSize: Style.space(32)
      readonly property int iconGap: Style.space(10)
      // Wide enough that the endmost icons clear the capsule's curved ends.
      readonly property int padX: Style.space(24)
      readonly property int padY: Style.space(8)
      readonly property int count: Math.max(1, root.resolvedPins.length)
      readonly property real availableWidth: panel.screenWidth * 0.86

      // Grow wider up to ~86% of screen width; past that, shrink icons to
      // fit — the same trade-off the real macOS dock makes.
      readonly property int naturalWidth: count * maxIconSize + (count - 1) * iconGap + padX * 2
      readonly property int iconSize: naturalWidth <= availableWidth
        ? maxIconSize
        : Math.max(minIconSize, Math.floor((availableWidth - padX * 2 - (count - 1) * iconGap) / count))

      readonly property int cardWidth: root.resolvedPins.length > 0
        ? (iconSize * count + iconGap * (count - 1) + padX * 2)
        : (maxIconSize + padX * 2)
      readonly property int cardHeight: iconSize + padY * 2
      // Extra vertical room above the pill so magnified/bouncing icons have
      // somewhere to rise into — and so the click-mask (sized to this whole
      // item) still covers them while they're up there.
      readonly property int headroom: Math.round(iconSize * (magStrength + 0.35))

      // ---- hover magnification ----
      property real hoverX: -100000
      readonly property real magRadius: iconSize * 2.1
      readonly property real magStrength: 0.85

      function scaleFor(centerX) {
        if (dockCard.hoverX < -99999) return 1.0
        var d = Math.abs(centerX - dockCard.hoverX)
        if (d >= dockCard.magRadius) return 1.0
        var t = 1 - d / dockCard.magRadius
        return 1.0 + dockCard.magStrength * t * t
      }

      BorderSurface {
        id: cardBg
        width: dockCard.cardWidth
        height: dockCard.cardHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Full capsule + near-opaque fill + 1px low-alpha hairline. The old
        // theme-driven look (small radius, 2px accent border, 0.92 alpha)
        // read as a boxy web panel: window edges behind bled through the
        // translucency as seams, and the bright border boxed it in. macOS
        // docks are a soft capsule with a border you barely register.
        radius: Math.round(height / 2)
        borderSpec: Border.flat(Util.alpha(Color.popups.border, 0.35), 1)
        // Vertical glass sheen: catches light at the top, settles darker at
        // the base. Derived from the theme background so it follows theme
        // switches instead of hardcoding a palette.
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(Color.popups.background, 2.1), 0.97) }
          GradientStop { position: 0.45; color: Util.alpha(Color.popups.background, 0.97) }
          GradientStop { position: 1.0; color: Util.alpha(Qt.darker(Color.popups.background, 1.5), 0.98) }
        }

        // Additive white sheen over the top half — the base color is dark
        // enough that lightening it multiplicatively (above) barely reads,
        // so the actual "glass" cue comes from this overlay, same as the
        // aqua-era gloss trick.
        Rectangle {
          anchors.fill: parent
          radius: parent.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.02) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
          }
        }
      }

      MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: dockCard.hoverX = mouseX
        onExited: dockCard.hoverX = -100000
      }

      Row {
        id: iconRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: dockCard.iconGap

        Repeater {
          model: root.resolvedPins

          delegate: Item {
            id: slot
            required property var modelData
            required property int index
            width: dockCard.iconSize
            height: dockCard.height

            readonly property real slotCenterX: iconRow.x + slot.x + width / 2
            readonly property real targetScale: dockCard.scaleFor(slotCenterX)
            property bool hovered: false
            readonly property var runningToplevel: root.toplevelFor(slot.modelData)
            readonly property bool isRunning: slot.runningToplevel !== null

            Rectangle {
              id: dot
              visible: slot.isRunning
              width: Style.space(5)
              height: Style.space(5)
              radius: width / 2
              color: Color.accent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(3)
            }

            Rectangle {
              id: tile
              width: dockCard.iconSize
              height: dockCard.iconSize
              radius: Style.space(12)
              color: slot.hovered ? Style.hoverFill : "transparent"
              anchors.horizontalCenter: parent.horizontalCenter
              // Anchored to the pill's own bottom (padY in from the edge),
              // not to the running-indicator dot below it — dot is a
              // separate overlay, and anchoring the icon to it always
              // reserved dot-height + extra padding beneath the icon with
              // nothing matching above it, pushing every icon off-center
              // upward regardless of whether that pin was even running.
              anchors.bottom: parent.bottom
              anchors.bottomMargin: dockCard.padY + tile.bounceOffset
              transformOrigin: Item.Bottom
              scale: slot.targetScale

              property real bounceOffset: 0

              Behavior on scale {
                SpringAnimation { spring: 3.2; damping: 0.28 }
              }

              SequentialAnimation {
                id: bounceAnim
                NumberAnimation { target: tile; property: "bounceOffset"; to: dockCard.iconSize * 0.45; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: tile; property: "bounceOffset"; to: 0; duration: 260; easing.type: Easing.OutBounce }
                NumberAnimation { target: tile; property: "bounceOffset"; to: dockCard.iconSize * 0.22; duration: 130; easing.type: Easing.OutQuad }
                NumberAnimation { target: tile; property: "bounceOffset"; to: 0; duration: 220; easing.type: Easing.OutBounce }
              }

              // Icons come from a mix of icon themes: some ship as
              // transparent art (Chromium, Neovim, Obsidian) that sits
              // cleanly on the dock, others bake in an opaque square
              // background (foot, btop, OBS, generic fallbacks) that reads
              // as a mismatched tile next to the rest. Clipping every icon
              // to one consistent rounded silhouette (same family as the
              // tile's own radius) makes the row read as one shape
              // language instead of a patchwork grid — a no-op for icons
              // that are already transparent, a real fix for the ones that
              // aren't.
              Image {
                id: icon
                anchors.fill: parent
                anchors.margins: Style.space(4)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                visible: false
                layer.enabled: true

                // Whatever icon theme resolves an app's default icon varies
                // wildly in polish — some ship clean art (Chromium, Neovim),
                // others fall back to a plain glyph on a flat square (foot,
                // the old btop/localsend renders). Papirus is a curated,
                // near-universal pack with consistently-styled art for
                // almost everything here, so prefer it explicitly and only
                // fall back to the normal themed lookup for the rare pin it
                // doesn't cover (e.g. omacalc, an Omarchy-only app).
                readonly property string papirusPath: "file:///usr/share/icons/Papirus/64x64/apps/" + slot.modelData.icon + ".svg"
                readonly property string themedPath: root.appLibrary ? root.appLibrary.iconSource(slot.modelData.icon) : ""

                source: icon.papirusPath
                onStatusChanged: {
                  if (status === Image.Error && source.toString() !== icon.themedPath) {
                    source = icon.themedPath
                  }
                }
              }

              Rectangle {
                id: iconMask
                anchors.fill: icon
                radius: Style.space(9)
                visible: false
                layer.enabled: true
              }

              MultiEffect {
                anchors.fill: icon
                source: icon
                maskEnabled: true
                maskSource: iconMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 0.05
              }
            }

            MouseArea {
              anchors.fill: tile
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: slot.hovered = true
              onExited: slot.hovered = false
              onClicked: {
                bounceAnim.start()
                root.launchOrFocus(slot.modelData, slot.runningToplevel)
              }
            }

            Rectangle {
              id: tooltip
              visible: opacity > 0
              opacity: slot.hovered ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 120 } }
              radius: Style.space(6)
              color: Util.alpha(Color.tooltip.background, 0.95)
              width: tooltipLabel.implicitWidth + Style.space(16)
              height: tooltipLabel.implicitHeight + Style.space(8)
              anchors.horizontalCenter: tile.horizontalCenter
              anchors.bottom: tile.top
              anchors.bottomMargin: Style.space(10) + dockCard.iconSize * (slot.targetScale - 1)

              Text {
                id: tooltipLabel
                anchors.centerIn: parent
                text: slot.modelData.name
                color: Color.tooltip.text
                font.family: Style.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
