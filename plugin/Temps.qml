import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "community.temps-fan-panel"

  property string label: "…"
  property string tooltip: ""
  property string profile: "?"
  property real cpuVal: 0
  property real gpuVal: 0
  property string fan1Val: "?"
  property string fan3Val: "?"
  property bool panelOpen: false

  readonly property color gpuColor: Qt.lighter(Color.accent, 1.55)
  readonly property real chartMin: 20
  readonly property real chartMax: 90

  property var cpuHistory: []
  property var gpuHistory: []
  readonly property int pollSeconds: 3
  readonly property int maxSamples: 1200  // 1h of history at pollSeconds resolution
  readonly property int displayPoints: 40 // chart is always drawn with this many points

  readonly property var timeRanges: [
    { id: "2m", label: "2m", seconds: 120 },
    { id: "10m", label: "10m", seconds: 600 },
    { id: "30m", label: "30m", seconds: 1800 },
    { id: "1h", label: "1h", seconds: 3600 }
  ]
  property string selectedRangeId: "2m"
  readonly property var selectedRange: {
    for (var i = 0; i < timeRanges.length; i++) if (timeRanges[i].id === selectedRangeId) return timeRanges[i]
    return timeRanges[0]
  }

  readonly property var profileList: [
    { id: "silent", name: "Silent" },
    { id: "quiet", name: "Quiet" },
    { id: "performance", name: "Performance" }
  ]

  function close() { root.panelOpen = false }
  function togglePanel() { root.panelOpen = !root.panelOpen }

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function setProfile(id) {
    setProc.command = ["sudo", "-n", "/usr/local/bin/fan-profile-set", id]
    setProc.running = true
  }

  function pushHistory(arr, value) {
    var h = arr.slice()
    h.push(value)
    if (h.length > root.maxSamples) h.shift()
    return h
  }

  // Last N raw samples covering the requested time window.
  function windowedHistory(history, rangeSeconds) {
    var n = Math.min(history.length, Math.max(1, Math.ceil(rangeSeconds / root.pollSeconds)))
    return history.slice(history.length - n)
  }

  // Reduces an array to at most targetPoints by averaging into buckets, so
  // the chart always draws the same number of points regardless of range.
  function downsample(arr, targetPoints) {
    if (arr.length <= targetPoints) return arr
    var out = []
    var bucketSize = arr.length / targetPoints
    for (var i = 0; i < targetPoints; i++) {
      var start = Math.floor(i * bucketSize)
      var end = Math.max(start + 1, Math.floor((i + 1) * bucketSize))
      var sum = 0, cnt = 0
      for (var j = start; j < end && j < arr.length; j++) { sum += arr[j]; cnt++ }
      out.push(cnt > 0 ? sum / cnt : arr[arr.length - 1])
    }
    return out
  }

  // Downsamples to however many of the displayPoints slots are actually
  // covered by real data yet — e.g. with 30s of data on a 2m range, this
  // returns ~10 points (25% of 40), not 40 stretched-out ones. linePoints
  // then places those against the FULL displayPoints width, so the line
  // only occupies its real proportion of the chart instead of always
  // stretching edge to edge.
  function chartHistory(history) {
    var rangeSeconds = root.selectedRange.seconds
    var fullRangeSamples = Math.max(1, Math.round(rangeSeconds / root.pollSeconds))
    var haveSamples = Math.min(history.length, fullRangeSamples)
    if (haveSamples === 0) return []
    var windowed = history.slice(history.length - haveSamples)
    var filledPoints = Math.max(1, Math.round((haveSamples / fullRangeSamples) * root.displayPoints))
    return root.downsample(windowed, Math.min(filledPoints, windowed.length))
  }

  // Maps a chartHistory() result to chart-space points (top-left origin).
  // x is scaled against the fixed displayPoints count (the full chart
  // width), not the array's own length, so a partially-filled array only
  // occupies its real share of the width.
  function linePoints(history, w, h) {
    var pts = []
    var n = history.length
    if (n === 0) return pts
    for (var i = 0; i < n; i++) {
      var x = root.displayPoints <= 1 ? w : (i / (root.displayPoints - 1)) * w
      var t = Math.max(root.chartMin, Math.min(root.chartMax, history[i]))
      var y = h - ((t - root.chartMin) / (root.chartMax - root.chartMin)) * h
      pts.push(Qt.point(x, y))
    }
    return pts
  }

  function areaPoints(history, w, h) {
    var pts = linePoints(history, w, h)
    if (pts.length === 0) return pts
    var closed = pts.slice()
    closed.push(Qt.point(pts[pts.length - 1].x, h))
    closed.push(Qt.point(pts[0].x, h))
    return closed
  }

  function update(text) {
    var cpu = "?", gpu = "?", fan1 = "?", fan3 = "?", prof = "?"
    var lines = text.trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq < 0) continue
      var k = lines[i].substring(0, eq).trim()
      var v = lines[i].substring(eq + 1).trim()
      if (k === "cpu") cpu = v
      else if (k === "gpu") gpu = v
      else if (k === "fan1") fan1 = v
      else if (k === "fan3") fan3 = v
      else if (k === "profile") prof = v
    }
    root.profile = prof
    root.fan1Val = fan1
    root.fan3Val = fan3

    var cpuNum = parseFloat(cpu)
    var gpuNum = parseFloat(gpu)
    if (!isNaN(cpuNum)) {
      root.cpuVal = cpuNum
      root.cpuHistory = root.pushHistory(root.cpuHistory, cpuNum)
    }
    if (!isNaN(gpuNum)) {
      root.gpuVal = gpuNum
      root.gpuHistory = root.pushHistory(root.gpuHistory, gpuNum)
    }

    root.label = "CPU " + cpu + "°  GPU " + gpu + "°"
    root.tooltip = "CPU " + cpu + "°C  ·  GPU " + gpu + "°C\nCPU_FAN " + fan1 + " RPM  ·  SYS_FAN2 " + fan3 + " RPM\nFan profile: " + prof + " — click for details"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: ["bash", Qt.resolvedUrl("read_temps.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
  }

  Process {
    id: setProc
    onExited: root.refresh()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    tooltipText: ""
    onPressed: root.togglePanel()
  }

  KeyboardPanel {
    id: detailsPanel
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.panelOpen
    contentWidth: Style.space(340)
    contentHeight: detailsPanel.fittedContentHeight(mainColumn.implicitHeight + 2)
    focusTarget: keyCatcher

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: mainColumn
        width: parent.width
        spacing: 16
        y: 2

        // ---- Hero readouts ----
        Row {
          width: parent.width

          Column {
            width: parent.width / 2
            spacing: -8
            Text {
              text: root.cpuVal.toFixed(0) + "°"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              // Hero read-out; deliberately oversized, outside Style.font.*
              font.pixelSize: 56
              font.bold: true
            }
            Text {
              text: "CPU"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }

          Column {
            width: parent.width / 2
            spacing: -8
            Text {
              text: root.gpuVal.toFixed(0) + "°"
              color: root.gpuColor
              font.family: root.bar.fontFamily
              // Hero read-out; deliberately oversized, outside Style.font.*
              font.pixelSize: 56
              font.bold: true
            }
            Text {
              text: "GPU"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }
        }

        Item { width: 1; height: 1 }

        // ---- Section caption + time range selector ----
        Item {
          width: parent.width
          height: Math.max(captionText.implicitHeight, rangeRow.implicitHeight)

          Text {
            id: captionText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "TEMPERATURE"
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          Row {
            id: rangeRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Repeater {
              model: root.timeRanges
              delegate: Rectangle {
                required property var modelData
                readonly property bool active: modelData.id === root.selectedRangeId
                width: 32
                height: 20
                radius: Style.cornerRadius
                color: active ? Color.accent : "transparent"
                border.width: active ? 0 : 1
                border.color: Qt.darker(root.bar.foreground, 2.2)

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: active ? Color.popups.background : Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall * 0.85
                  font.bold: active
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedRangeId = modelData.id
                }
              }
            }
          }
        }

        // ---- Line + area chart ----
        Item {
          id: chartArea
          width: parent.width
          height: 80

          Shape {
            id: cpuArea
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeWidth: -1
              fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: chartArea.height
                GradientStop { position: 0.0; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.28) }
                GradientStop { position: 1.0; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.0) }
              }
              PathPolyline { path: root.areaPoints(root.chartHistory(root.cpuHistory), chartArea.width, chartArea.height) }
            }
          }
          Shape {
            id: gpuArea
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeWidth: -1
              fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: chartArea.height
                GradientStop { position: 0.0; color: Qt.rgba(root.gpuColor.r, root.gpuColor.g, root.gpuColor.b, 0.18) }
                GradientStop { position: 1.0; color: Qt.rgba(root.gpuColor.r, root.gpuColor.g, root.gpuColor.b, 0.0) }
              }
              PathPolyline { path: root.areaPoints(root.chartHistory(root.gpuHistory), chartArea.width, chartArea.height) }
            }
          }
          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeWidth: 2
              strokeColor: Color.accent
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin
              PathPolyline { path: root.linePoints(root.chartHistory(root.cpuHistory), chartArea.width, chartArea.height) }
            }
            ShapePath {
              strokeWidth: 2
              strokeColor: root.gpuColor
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin
              PathPolyline { path: root.linePoints(root.chartHistory(root.gpuHistory), chartArea.width, chartArea.height) }
            }
          }
        }

        // ---- Legend ----
        Row {
          spacing: 16
          Row {
            spacing: 6
            Rectangle { width: 10; height: 2; radius: 1; color: Color.accent; anchors.verticalCenter: parent.verticalCenter }
            Text {
              text: "cpu"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          Row {
            spacing: 6
            Rectangle { width: 10; height: 2; radius: 1; color: root.gpuColor; anchors.verticalCenter: parent.verticalCenter }
            Text {
              text: "gpu"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.bar.foreground
          opacity: 0.12
        }

        // ---- Fan stat grid ----
        Column {
          width: parent.width
          spacing: 10

          Row {
            width: parent.width
            Column {
              width: parent.width / 2
              spacing: 2
              Text {
                text: "CPU_FAN"
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.fan1Val + " rpm"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
            }
            Column {
              width: parent.width / 2
              spacing: 2
              Text {
                text: "SYS_FAN2"
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: root.fan3Val + " rpm"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.bar.foreground
          opacity: 0.12
        }

        // ---- Profile tabs ----
        Column {
          width: parent.width
          spacing: 8

          Text {
            text: "FAN PROFILE"
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          Row {
            width: parent.width
            height: 50
            spacing: 8

            Repeater {
              model: root.profileList
              delegate: Rectangle {
                required property var modelData
                readonly property bool active: modelData.id === root.profile
                width: (mainColumn.width - 8 * (root.profileList.length - 1)) / root.profileList.length
                height: 50
                radius: Style.cornerRadius
                color: active ? Color.accent : "transparent"
                border.width: 1
                border.color: active ? Color.accent : Qt.darker(root.bar.foreground, 2.2)

                Text {
                  anchors.centerIn: parent
                  width: parent.width - 6
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: modelData.name.toUpperCase()
                  color: active ? Color.popups.background : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall * 0.85
                  font.bold: active
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setProfile(modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
