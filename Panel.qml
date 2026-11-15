import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// The bar icon and its panel: battery, the noise control mode, and what the
// computer does when an AirPod comes out. Everything belongs to the service.
Panel {
  id: root
  moduleName: "bhj.airpods"
  ipcTarget: "bhj.airpods"

  readonly property var service: bar?.shell?.serviceFor("bhj.airpods") ?? null
  readonly property bool connected: service ? service.connected : false
  readonly property var battery: service ? service.battery : ({})
  readonly property var ears: service ? service.ears : []
  readonly property string mode: service ? service.mode : ""
  readonly property string known: service ? service.known : ""
  readonly property bool connecting: service ? service.connecting : false

  property string focusSection: "modes"
  property int selectedIndex: 0
  property bool cursorActive: false
  property real wheelAccumulator: 0

  // The lower of the two AirPods, which is the one that runs out first.
  readonly property int lowest: {
    var levels = []
    if (battery.left) levels.push(battery.left.level)
    if (battery.right) levels.push(battery.right.level)
    if (battery.headphone) levels.push(battery.headphone.level)
    return levels.length ? Math.min.apply(null, levels) : -1
  }

  readonly property var modes: {
    var list = []
    if (service && (service.allowOff || mode === "off")) list.push({ value: "off", title: "Off", detail: "No noise control" })
    list.push({ value: "transparency", title: "Transparency", detail: "Lets the room in" })
    list.push({ value: "adaptive", title: "Adaptive", detail: "Blends the two as the room changes" })
    list.push({ value: "anc", title: "Noise cancelling", detail: "Shuts the room out" })
    return list
  }

  readonly property var batteryRows: {
    var list = []
    if (battery.headphone) list.push({ title: "AirPods", part: battery.headphone })
    if (battery.left) list.push({ title: "Left", part: battery.left })
    if (battery.right) list.push({ title: "Right", part: battery.right })
    if (battery.case) list.push({ title: "Case", part: battery.case })
    return list
  }

  readonly property string wearing: {
    if (ears.length < 2) return ""
    var inEar = 0, inCase = 0
    for (var i = 0; i < ears.length; i++) {
      if (ears[i] === "ear") inEar++
      else if (ears[i] === "case") inCase++
    }
    if (inEar === 2) return "Both in your ears"
    if (inEar === 1) return "One in your ear"
    if (inCase === 2) return "Both in the case"
    return "Neither in your ears"
  }

  readonly property string hint: {
    if (!connected) {
      if (service && service.error !== "") return service.error
      if (connecting) return "Connecting…"
      if (known !== "") return "Paired, but not connected to this computer."
      return "None paired. Pair them from the Bluetooth panel."
    }
    return wearing
  }

  readonly property var toggles: ["autopause", "conversation", "duck"]

  function modeIndex() {
    for (var i = 0; i < modes.length; i++) if (modes[i].value === mode) return i
    return 0
  }

  function cycleMode(delta) {
    if (!connected || !service || !modes.length) return
    var next = (modeIndex() + delta + modes.length) % modes.length
    service.setMode(modes[next].value)
  }

  // Top to bottom: the modes, then the three switches.
  function moveCursor(delta) {
    if (!connected) return
    if (focusSection === "modes") {
      var next = selectedIndex + delta
      if (next < 0) return
      if (next > modes.length - 1) {
        focusSection = toggles[0]
        return
      }
      selectedIndex = next
      return
    }
    var at = toggles.indexOf(focusSection) + delta
    if (at < 0) {
      focusSection = "modes"
      selectedIndex = modes.length - 1
    } else if (at < toggles.length) {
      focusSection = toggles[at]
    }
  }

  function activate() {
    if (!service) return
    if (!connected) {
      service.connect()
      return
    }
    if (focusSection === "modes") {
      if (selectedIndex >= 0 && selectedIndex < modes.length) service.setMode(modes[selectedIndex].value)
    } else if (focusSection === "autopause") {
      service.setAutopause(!service.autopause)
    } else if (focusSection === "conversation") {
      service.setConversation(!service.conversation)
    } else if (focusSection === "duck") {
      service.setDuck(!service.duck)
    }
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var top = item.mapToItem(flick.contentItem || flick, 0, 0).y
    var bottom = top + (item.height || 0)
    var margin = 6
    if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > flick.contentY + flick.height - margin) flick.contentY = bottom + margin - flick.height
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened) return
    focusSection = "modes"
    selectedIndex = modeIndex()
    cursorActive = false
    if (service) service.sync()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱡏"
    labelText: root.connected && root.lowest >= 0 && !vertical ? root.lowest + "%" : ""
    slotSize: Style.bar.iconSlot * (labelText !== "" ? 2 : 1)
    opacity: root.connected ? 1 : 0.45
    tooltipText: !root.connected ? (root.known !== "" ? root.known + ": not connected" : "AirPods: none paired")
      : (root.service.name || "AirPods") + (root.lowest >= 0 ? ": " + root.lowest + "%" : "")
    onPressed: root.toggle()
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.cycleMode(wheel.steps > 0 ? 1 : -1)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󱡏"
              color: root.bar.foreground
              opacity: root.connected ? 1 : 0.45
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: root.connected && root.service.name !== "" ? root.service.name
                  : root.known !== "" ? root.known : "AirPods"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                visible: text !== ""
                text: root.hint
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }
          }

          CursorSurface {
            id: connectRow
            visible: !root.connected && root.known !== ""
            width: parent.width
            implicitHeight: connectText.implicitHeight + Style.space(16)
            hasCursor: root.cursorActive || connectMouse.containsMouse
            bordered: true
            foreground: root.bar.foreground
            opacity: root.connecting ? 0.55 : 1

            Column {
              id: connectText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(1)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.connecting ? "Connecting…" : "Connect to this computer"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Takes them over from your phone"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: connectMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.service && !root.connecting) root.service.connect()
            }
          }

          PanelSeparator {
            visible: root.connected
            foreground: root.bar.foreground
          }

          Column {
            visible: root.connected && root.batteryRows.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "BATTERY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.batteryRows

              Item {
                id: cell
                required property var modelData
                readonly property bool stale: modelData.part.stale === true
                width: parent.width
                implicitHeight: cellName.implicitHeight + Style.space(4)
                opacity: stale ? 0.55 : 1

                Text {
                  id: cellName
                  textFormat: Text.PlainText
                  text: cell.modelData.title
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(52)
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                  id: track
                  anchors.left: cellName.right
                  anchors.right: cellValue.left
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16)

                  Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, cell.modelData.part.level)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: cell.modelData.part.level <= 20 && !cell.modelData.part.charging
                      ? Commons.Color.urgent : root.bar.foreground
                  }
                }

                Text {
                  id: cellValue
                  textFormat: Text.PlainText
                  text: (cell.modelData.part.charging ? "󱐋 " : "") + cell.modelData.part.level + "%"
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  horizontalAlignment: Text.AlignRight
                  width: Style.space(58)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          PanelSeparator {
            visible: root.connected
            foreground: root.bar.foreground
          }

          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "NOISE CONTROL"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.modes

              CursorSurface {
                id: row
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: rowText.implicitHeight + Style.space(12)
                hasCursor: root.cursorActive && root.focusSection === "modes" && root.selectedIndex === index
                current: root.mode === modelData.value
                foreground: root.bar.foreground
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(row)

                Column {
                  id: rowText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.modelData.title
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.modelData.detail
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.focusSection = "modes"
                    root.selectedIndex = row.index
                  }
                  onClicked: if (root.service) root.service.setMode(row.modelData.value)
                }
              }
            }
          }

          PanelSeparator {
            visible: root.connected
            foreground: root.bar.foreground
          }

          Toggle {
            id: autopauseToggle
            visible: root.connected
            width: parent.width
            label: "Pause when one comes out"
            description: "Pauses what is playing, and carries on when both are back in"
            checked: root.service ? root.service.autopause : false
            hasCursor: root.cursorActive && root.focusSection === "autopause"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(autopauseToggle)
            onHovered: function(on) {
              if (!on) return
              root.cursorActive = true
              root.focusSection = "autopause"
            }
            onClicked: if (root.service) root.service.setAutopause(!root.service.autopause)
          }

          Toggle {
            id: conversationToggle
            visible: root.connected
            width: parent.width
            label: "Conversational awareness"
            description: "The AirPods let voices through when you start talking"
            checked: root.service ? root.service.conversation : false
            hasCursor: root.cursorActive && root.focusSection === "conversation"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(conversationToggle)
            onHovered: function(on) {
              if (!on) return
              root.cursorActive = true
              root.focusSection = "conversation"
            }
            onClicked: if (root.service) root.service.setConversation(!root.service.conversation)
          }

          Toggle {
            id: duckToggle
            visible: root.connected
            width: parent.width
            label: "Lower the volume as you talk"
            description: "With conversational awareness on, and back up when you stop"
            checked: root.service ? root.service.duck : false
            hasCursor: root.cursorActive && root.focusSection === "duck"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(duckToggle)
            onHovered: function(on) {
              if (!on) return
              root.cursorActive = true
              root.focusSection = "duck"
            }
            onClicked: if (root.service) root.service.setDuck(!root.service.duck)
          }
        }
      }
    }
  }
}
