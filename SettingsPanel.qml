import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Full-screen overlay with a settings card. Opened from the dock's
// right-click menu. Writes the same JSON files the dock watches, so the
// dock, this panel, and any editor stay in sync.
PanelWindow {
  id: settingsWindow

  property var dock: null
  property bool open: false
  property string page: "visibility"

  signal requestClose()

  visible: open
  screen: dock && dock.targetScreen ? dock.targetScreen : null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-dock-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  anchors { top: true; bottom: true; left: true; right: true }

  readonly property color fg: Color.popups.text
  readonly property color bg: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property int cardWidth: Style.space(760)
  readonly property int cardHeight: Math.round((settingsWindow.screen ? settingsWindow.screen.height : 900) * 0.72)
  readonly property int sidebarWidth: Style.space(168)

  readonly property var fakeBar: QtObject {
    readonly property color foreground: settingsWindow.fg
    readonly property color background: settingsWindow.bg
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: settingsWindow.fontFamily
  }

  readonly property var monitorOptions: {
    var out = [{ value: "", label: "Primary screen" }]
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      var name = String(s.name || "")
      var model = String(s.model || "")
      var label = model.length > 0 && name.length > 0 ? (model + " · " + name)
        : (model || name || ("Screen " + (i + 1)))
      out.push({ value: name, label: label })
    }
    return out
  }

  readonly property var pinOptions: {
    var lib = dock && dock.appLibrary ? dock.appLibrary : null
    if (!lib || typeof lib.sortedEntries !== "function") return []
    var entries = lib.sortedEntries("") || []
    var out = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (!e || !e.id) continue
      out.push({ value: String(e.id), label: String(e.name || e.id) })
    }
    return out
  }

  readonly property var navItems: [
    { id: "visibility", label: "Visibility" },
    { id: "size", label: "Size" },
    { id: "look", label: "Look" },
    { id: "feel", label: "Feel" },
    { id: "pins", label: "Pinned" }
  ]

  function cfg(key, fallback) {
    if (!dock) return fallback
    var v = dock[key]
    return v === undefined || v === null ? fallback : v
  }

  function set(key, value) {
    if (dock && typeof dock.setSetting === "function") dock.setSetting(key, value)
  }

  function currentMonitorValue() {
    var match = String((dock && dock.monitorMatch) || "")
    if (match.length === 0) return ""
    var opts = monitorOptions
    for (var i = 0; i < opts.length; i++) {
      if (String(opts[i].value).toLowerCase() === match) return opts[i].value
    }
    return match
  }

  onOpenChanged: {
    if (open && dock && dock.appLibrary && typeof dock.appLibrary.refreshIcons === "function")
      dock.appLibrary.refreshIcons()
  }

  MouseArea {
    id: dismissArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: settingsWindow.requestClose()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.38)
  }

  BorderSurface {
    id: card
    width: Math.min(settingsWindow.cardWidth, parent.width - Style.space(40))
    height: Math.min(settingsWindow.cardHeight, parent.height - Style.space(40))
    anchors.centerIn: parent
    radius: Style.cornerRadius > 0 ? Style.space(16) : 0
    color: Util.alpha(settingsWindow.bg, 0.98)
    borderSpec: Border.flat(Util.alpha(Color.popups.border, 0.55), 1)
    focus: settingsWindow.open
    Keys.onEscapePressed: settingsWindow.requestClose()

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onClicked: {}
    }

    // Trackpad/wheel must not scroll the page or nudge sliders.
    // Sliders are click-and-drag only.
    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) { event.accepted = true }
    }

    component SettingSlider: Column {
      id: sliderRow
      property string label: ""
      property string suffix: ""
      property real from: 0
      property real to: 100
      property real value: 0
      property real step: 1
      property bool integer: true
      signal changed(real v)
      width: parent ? parent.width : 0
      spacing: Style.space(4)

      Row {
        width: parent.width
        Text {
          text: sliderRow.label
          textFormat: Text.PlainText
          color: Qt.darker(settingsWindow.fg, 1.4)
          font.family: settingsWindow.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: parent.width - valueLabel.width
          elide: Text.ElideRight
        }
        Text {
          id: valueLabel
          text: (sliderRow.integer ? Math.round(sliderRow.value) : sliderRow.value.toFixed(1)) + sliderRow.suffix
          textFormat: Text.PlainText
          color: settingsWindow.fg
          font.family: settingsWindow.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelSlider {
        width: parent.width
        bar: settingsWindow.fakeBar
        minimum: sliderRow.from
        maximum: sliderRow.to
        value: sliderRow.value
        step: sliderRow.step
        integer: sliderRow.integer
        onMoved: function(v) { if (dragging) sliderRow.changed(v) }
        onReleased: function(v) { sliderRow.changed(v) }
      }
    }

    Row {
      id: headerRow
      width: parent.width - Style.space(32)
      x: Style.space(16)
      y: Style.space(14)
      spacing: Style.space(12)

      Column {
        width: parent.width - closeBtn.width - parent.spacing
        spacing: Style.space(2)

        Text {
          text: "Dock Settings"
          textFormat: Text.PlainText
          color: settingsWindow.fg
          font.family: settingsWindow.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          text: "Changes apply immediately."
          textFormat: Text.PlainText
          color: Qt.darker(settingsWindow.fg, 1.4)
          font.family: settingsWindow.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        id: closeBtn
        text: "Close"
        foreground: settingsWindow.fg
        accent: settingsWindow.accent
        bordered: true
        onClicked: settingsWindow.requestClose()
      }
    }

    Rectangle {
      id: headerRule
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: headerRow.bottom
      anchors.topMargin: Style.space(12)
      height: 1
      color: Qt.rgba(settingsWindow.fg.r, settingsWindow.fg.g, settingsWindow.fg.b, 0.12)
    }

    Item {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: headerRule.bottom
      anchors.bottom: parent.bottom

      Column {
        id: sidebar
        width: settingsWindow.sidebarWidth
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottomMargin: Style.space(12)
        anchors.leftMargin: Style.space(12)
        spacing: Style.space(4)

        Repeater {
          model: settingsWindow.navItems
          delegate: Button {
            required property var modelData
            width: sidebar.width
            text: modelData.label
            leftAlign: true
            selected: settingsWindow.page === modelData.id
            foreground: settingsWindow.fg
            accent: settingsWindow.accent
            onClicked: settingsWindow.page = modelData.id
          }
        }

        Item { width: 1; height: Style.space(12) }

        Button {
          width: sidebar.width
          text: "Reset all"
          bordered: true
          foreground: settingsWindow.fg
          accent: settingsWindow.accent
          onClicked: {
            if (dock && typeof dock.resetSettings === "function") dock.resetSettings()
          }
        }
      }

      Rectangle {
        id: sideRule
        width: 1
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Qt.rgba(settingsWindow.fg.r, settingsWindow.fg.g, settingsWindow.fg.b, 0.12)
      }

      Flickable {
        id: pageFlick
        anchors.left: sideRule.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(16)
        anchors.rightMargin: Style.space(16)
        anchors.topMargin: Style.space(12)
        anchors.bottomMargin: Style.space(16)
        clip: true
        contentWidth: width
        contentHeight: pageStack.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: false

        Column {
          id: pageStack
          width: pageFlick.width
          spacing: Style.space(12)

          Column {
            visible: settingsWindow.page === "visibility"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "Visibility"
              foreground: settingsWindow.fg
              fontFamily: settingsWindow.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Show dock"
              description: "Hide the dock entirely. A small chip stays so you can open settings again."
              checked: settingsWindow.cfg("dockEnabled", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("dockEnabled", !settingsWindow.cfg("dockEnabled", true))
            }

            Toggle {
              width: parent.width
              label: "Auto-hide"
              description: "Slide off-screen when the pointer leaves. Reveal from the bottom edge."
              checked: settingsWindow.cfg("autohide", false)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("autohide", !settingsWindow.cfg("autohide", false))
            }

            SettingSlider {
              visible: settingsWindow.cfg("autohide", false)
              label: "Hide delay"
              suffix: " ms"
              from: 200
              to: 2000
              step: 50
              value: settingsWindow.cfg("autohideDelay", 700)
              onChanged: function(v) { settingsWindow.set("autohideDelay", Math.round(v)) }
            }

            Toggle {
              width: parent.width
              label: "Float over windows"
              description: "On: overlay tiled windows. Off: reserve the dock strip so tiles stop above it."
              checked: settingsWindow.cfg("overlayMode", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("overlayMode", !settingsWindow.cfg("overlayMode", true))
            }

            SettingSlider {
              visible: !settingsWindow.cfg("overlayMode", true)
              label: "Gap to windows"
              suffix: " px"
              from: 0
              to: 16
              value: settingsWindow.cfg("windowGap", 2)
              onChanged: function(v) { settingsWindow.set("windowGap", Math.round(v)) }
            }

            Dropdown {
              width: parent.width
              label: "Monitor"
              value: settingsWindow.currentMonitorValue()
              options: settingsWindow.monitorOptions
              foreground: settingsWindow.fg
              background: settingsWindow.bg
              accent: settingsWindow.accent
              onChanged: function(v) {
                if (dock && typeof dock.writeMonitor === "function") dock.writeMonitor(v)
              }
            }
          }

          Column {
            visible: settingsWindow.page === "size"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "Size"
              foreground: settingsWindow.fg
              fontFamily: settingsWindow.fontFamily
            }

            SettingSlider {
              label: "Icon size"
              suffix: " px"
              from: 24
              to: 80
              value: settingsWindow.cfg("iconSize", 50)
              onChanged: function(v) { settingsWindow.set("iconSize", Math.round(v)) }
            }

            SettingSlider {
              label: "Minimum icon size (when the dock is crowded)"
              suffix: " px"
              from: 16
              to: 64
              value: settingsWindow.cfg("minIconSize", 32)
              onChanged: function(v) { settingsWindow.set("minIconSize", Math.round(v)) }
            }

            SettingSlider {
              label: "Gap between icons"
              suffix: " px"
              from: 0
              to: 28
              value: settingsWindow.cfg("iconGap", 10)
              onChanged: function(v) { settingsWindow.set("iconGap", Math.round(v)) }
            }

            SettingSlider {
              label: "Horizontal padding"
              suffix: " px"
              from: 0
              to: 48
              value: settingsWindow.cfg("paddingX", 24)
              onChanged: function(v) { settingsWindow.set("paddingX", Math.round(v)) }
            }

            SettingSlider {
              label: "Vertical padding"
              suffix: " px"
              from: 0
              to: 24
              value: settingsWindow.cfg("paddingY", 8)
              onChanged: function(v) { settingsWindow.set("paddingY", Math.round(v)) }
            }

            SettingSlider {
              label: "Distance from screen edge"
              suffix: " px"
              from: 0
              to: 48
              value: settingsWindow.cfg("edgeMargin", 10)
              onChanged: function(v) { settingsWindow.set("edgeMargin", Math.round(v)) }
            }

            SettingSlider {
              label: "Maximum dock width"
              suffix: "%"
              from: 50
              to: 100
              value: settingsWindow.cfg("maxWidthPercent", 86)
              onChanged: function(v) { settingsWindow.set("maxWidthPercent", Math.round(v)) }
            }
          }

          Column {
            visible: settingsWindow.page === "look"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "Look"
              foreground: settingsWindow.fg
              fontFamily: settingsWindow.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Rounded capsule"
              description: "Pill-shaped dock. Off is a rectangular bar, matching Omarchy."
              checked: settingsWindow.cfg("capsule", false)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("capsule", !settingsWindow.cfg("capsule", false))
            }

            Toggle {
              width: parent.width
              label: "Glass fill"
              description: "Gradient glass capsule. Off is a flat panel fill."
              checked: settingsWindow.cfg("glassmorphism", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("glassmorphism", !settingsWindow.cfg("glassmorphism", true))
            }

            Toggle {
              width: parent.width
              label: "Top sheen"
              description: "Soft highlight across the top of the capsule."
              checked: settingsWindow.cfg("sheen", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("sheen", !settingsWindow.cfg("sheen", true))
            }

            SettingSlider {
              label: "Background opacity"
              suffix: "%"
              from: 10
              to: 100
              value: settingsWindow.cfg("backgroundOpacity", 52)
              onChanged: function(v) { settingsWindow.set("backgroundOpacity", Math.round(v)) }
            }

            SettingSlider {
              label: "Border width"
              suffix: " px"
              from: 0
              to: 6
              value: settingsWindow.cfg("borderWidth", 2)
              onChanged: function(v) { settingsWindow.set("borderWidth", Math.round(v)) }
            }

            SettingSlider {
              label: "Border opacity"
              suffix: "%"
              from: 0
              to: 100
              value: settingsWindow.cfg("borderOpacity", 100)
              onChanged: function(v) { settingsWindow.set("borderOpacity", Math.round(v)) }
            }

            Toggle {
              width: parent.width
              label: "Running indicators"
              description: "Accent dot under apps that have an open window."
              checked: settingsWindow.cfg("showBadges", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("showBadges", !settingsWindow.cfg("showBadges", true))
            }

            Toggle {
              width: parent.width
              label: "Tooltips"
              description: "Show the app name above an icon on hover."
              checked: settingsWindow.cfg("showTooltips", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("showTooltips", !settingsWindow.cfg("showTooltips", true))
            }
          }

          Column {
            visible: settingsWindow.page === "feel"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "Feel"
              foreground: settingsWindow.fg
              fontFamily: settingsWindow.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Resize icons on hover"
              description: "Grow icons under the pointer. Set amount to 0 for no resize."
              checked: settingsWindow.cfg("magnify", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("magnify", !settingsWindow.cfg("magnify", true))
            }

            SettingSlider {
              visible: settingsWindow.cfg("magnify", true)
              label: "Hover resize"
              suffix: "%"
              from: 0
              to: 150
              value: settingsWindow.cfg("magnifyStrength", 85)
              onChanged: function(v) { settingsWindow.set("magnifyStrength", Math.round(v)) }
            }

            SettingSlider {
              visible: settingsWindow.cfg("magnify", true) && settingsWindow.cfg("magnifyStrength", 85) > 0
              label: "Hover resize spread"
              suffix: "%"
              from: 100
              to: 400
              value: settingsWindow.cfg("magnifyRadius", 210)
              onChanged: function(v) { settingsWindow.set("magnifyRadius", Math.round(v)) }
            }

            Toggle {
              width: parent.width
              label: "Launch bounce"
              description: "Bounce the icon when launching an app that is not already running."
              checked: settingsWindow.cfg("launchBounce", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("launchBounce", !settingsWindow.cfg("launchBounce", true))
            }

            Toggle {
              width: parent.width
              label: "Show running apps"
              description: "Unpinned open apps appear to the right of a divider."
              checked: settingsWindow.cfg("showRunningApps", true)
              foreground: settingsWindow.fg
              accent: settingsWindow.accent
              onClicked: settingsWindow.set("showRunningApps", !settingsWindow.cfg("showRunningApps", true))
            }
          }

          Column {
            visible: settingsWindow.page === "pins"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "Pinned apps"
              foreground: settingsWindow.fg
              fontFamily: settingsWindow.fontFamily
            }

            Text {
              width: parent.width
              text: "Drag icons on the dock to reorder. Right-click an icon to pin or unpin."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: Qt.darker(settingsWindow.fg, 1.4)
              font.family: settingsWindow.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: (dock && dock.resolvedPins) ? dock.resolvedPins : []

              delegate: Row {
                required property var modelData
                required property int index
                width: pageStack.width
                spacing: Style.space(10)

                Text {
                  text: String((index + 1)) + "."
                  width: Style.space(24)
                  color: Qt.darker(settingsWindow.fg, 1.4)
                  font.family: settingsWindow.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: String(modelData.name || modelData.id || "")
                  width: parent.width - Style.space(24) - unpinBtn.width - parent.spacing * 2
                  elide: Text.ElideRight
                  color: settingsWindow.fg
                  font.family: settingsWindow.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
                Button {
                  id: unpinBtn
                  text: "Unpin"
                  foreground: settingsWindow.fg
                  accent: settingsWindow.accent
                  onClicked: {
                    if (dock && typeof dock.unpinApp === "function")
                      dock.unpinApp(String(modelData.id || ""))
                  }
                }
              }
            }

            SearchableDropdown {
              width: parent.width
              label: "Add pinned app"
              placeholderText: "Search installed apps…"
              emptyText: "No matching apps"
              value: ""
              options: settingsWindow.pinOptions
              foreground: settingsWindow.fg
              background: settingsWindow.bg
              accent: settingsWindow.accent
              onChanged: function(v) {
                if (dock && typeof dock.pinApp === "function") dock.pinApp(v)
              }
            }
          }
        }
      }
    }
  }
}
