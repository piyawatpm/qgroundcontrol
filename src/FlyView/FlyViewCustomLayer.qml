import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

// ═══════════════════════════════════════════════════════════════════
// Viewpro Camera Overlay — Direct TCP ViewLink Control
//
// Gestures on video:
//   Tap          → auto-focus + ring animation (ViewLink C1)
//   Hold + drag  → gimbal speed control + arrow indicator (ViewLink A1)
//
// Bottom bar: Zoom, Photo, Record, Source, WHT, Home, Lock, Track, More
// ═══════════════════════════════════════════════════════════════════
Item {
    id: _root

    // ── Required by FlyView ──────────────────────────────────────
    property var parentToolInsets
    property var totalToolInsets:    _toolInsets
    property var mapControl

    // ── ViewLink controller (direct TCP to camera) ───────────────
    property var  _vl: QGroundControl.viewLinkController

    // ── Overlay state ────────────────────────────────────────────
    property bool _recording:    false
    property int  _srcIdx:       0
    property bool _trackMode:    false
    property real _joyPitch:     0
    property real _joyYaw:       0
    property bool _dragging:     false
    property int  _touchCount:   0
    property int  _paletteIdx:   0      // 0=WHT, 1=BLK, 2=RAIN, 3=LAVA
    property bool _gimbalLocked: false   // lock/follow toggle state
    property bool _morePanel:    false   // expanded panel visible

    // ── Camera source table ──────────────────────────────────────
    readonly property var _sources: [
        { id: 0, label: "EO"   },
        { id: 1, label: "IR"   },
        { id: 2, label: "PIP"  },
        { id: 3, label: "PIP2" }
    ]

    // ── Thermal color palette table ──────────────────────────────
    readonly property var _palettes: [
        { id: 0, label: "WHT"  },
        { id: 1, label: "BLK"  },
        { id: 2, label: "RAIN" },
        { id: 3, label: "LAVA" }
    ]

    // ── Layout constants ─────────────────────────────────────────
    readonly property real _btnH:       ScreenTools.defaultFontPixelHeight * (ScreenTools.isMobile ? 2.8 : 2.2)
    readonly property real _btnW:       _btnH * 1.3
    readonly property real _gap:        ScreenTools.defaultFontPixelWidth * 0.5
    readonly property real _margin:     ScreenTools.defaultFontPixelWidth
    readonly property real _fontSize:   ScreenTools.defaultFontPointSize * 0.85

    QGCPalette { id: qgcPal }

    // ── Tool insets ──────────────────────────────────────────────
    QGCToolInsets {
        id:                     _toolInsets
        leftEdgeTopInset:       parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset:    parentToolInsets.leftEdgeCenterInset
        leftEdgeBottomInset:    parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      parentToolInsets.rightEdgeTopInset
        rightEdgeCenterInset:   parentToolInsets.rightEdgeCenterInset
        rightEdgeBottomInset:   parentToolInsets.rightEdgeBottomInset
        topEdgeLeftInset:       parentToolInsets.topEdgeLeftInset
        topEdgeCenterInset:     parentToolInsets.topEdgeCenterInset
        topEdgeRightInset:      parentToolInsets.topEdgeRightInset
        bottomEdgeLeftInset:    parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset:  bottomBar.visible ? (_root.height - bottomBar.y) : parentToolInsets.bottomEdgeCenterInset
        bottomEdgeRightInset:   parentToolInsets.bottomEdgeRightInset
    }

    Component.onCompleted: {
        if (_vl && !_vl.connected) {
            _vl.connectToCamera("192.168.144.119", 2000)
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  VERSION LABEL (top-right corner)
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        z: 100
        anchors {
            top:        parent.top
            right:      parent.right
            topMargin:  4
            rightMargin: 4
        }
        width:  versionLabel.implicitWidth + 12
        height: versionLabel.implicitHeight + 6
        radius: 4
        color:  "#88000000"

        Text {
            id: versionLabel
            anchors.centerIn: parent
            font.pixelSize: 11
            font.bold: true
            color: "#CCCCCC"
            text: "v1.13"
        }
    }

    // CONNECTION STATUS label removed (v1.11)

    // ═════════════════════════════════════════════════════════════
    //  FULL-SCREEN TOUCH AREA
    //
    //  Tap         = auto-focus + ring animation
    //  Hold + drag = gimbal speed + direction line
    // ═════════════════════════════════════════════════════════════
    MouseArea {
        id: videoTouchArea
        anchors.fill: parent
        z: 0
        // propagateComposedEvents allows double-click to pass through
        // but we handle single press/release ourselves
        propagateComposedEvents: true

        property real pressX: 0
        property real pressY: 0
        property bool didDrag: false

        onPressed: (mouse) => {
            pressX  = mouse.x
            pressY  = mouse.y
            didDrag = false
            _touchCount++

            // Show press indicator
            pressIndicator.x = mouse.x - pressIndicator.width / 2
            pressIndicator.y = mouse.y - pressIndicator.height / 2
            pressIndicator.opacity = 0.8
            // Accept the event (don't propagate press)
            mouse.accepted = true
        }

        onPositionChanged: (mouse) => {
            var dx = mouse.x - pressX
            var dy = mouse.y - pressY
            var dist = Math.sqrt(dx * dx + dy * dy)

            // 10px deadzone before starting drag
            if (!didDrag && dist < 10)
                return

            if (!didDrag) {
                didDrag    = true
                _dragging  = true
            }

            // Update drag line visual
            dragLine.x1 = pressX
            dragLine.y1 = pressY
            dragLine.x2 = mouse.x
            dragLine.y2 = mouse.y
            dragLine.visible = true

            // Convert drag to gimbal speed: max ±30 deg/s at 150px
            var maxDrag = 150.0
            _joyYaw   =  Math.max(-30, Math.min(30, (dx / maxDrag) * 30))
            _joyPitch = -Math.max(-30, Math.min(30, (dy / maxDrag) * 30))

            // Hide press indicator during drag
            pressIndicator.opacity = 0
        }

        onReleased: (mouse) => {
            dragLine.visible = false
            pressIndicator.opacity = 0

            if (didDrag) {
                _joyYaw   = 0
                _joyPitch = 0
                _dragging = false
                if (_vl) _vl.gimbalSpeed(0, 0)
            } else {
                if (_trackMode) {
                    var nx = mouse.x / _root.width
                    var ny = mouse.y / _root.height
                    if (_vl) _vl.trackPoint(nx, ny)
                    _trackMode = false
                } else {
                    if (_vl) _vl.autoFocus()
                }

                tapRing.x = mouse.x - tapRing.width / 2
                tapRing.y = mouse.y - tapRing.height / 2
                tapRingAnim.restart()
            }
        }
    }

    // ── Gimbal rate sender: 10 Hz while dragging ──
    Timer {
        interval: 100
        repeat:   true
        running:  _dragging
        onTriggered: {
            if (_vl) {
                _vl.gimbalSpeed(_joyYaw, _joyPitch)
            }
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  TAP ANIMATION — expanding ring at tap point
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        id: tapRing
        width: 60; height: 60; radius: 30
        color: "transparent"
        border.color: "#33FF33"
        border.width: 3
        opacity: 0
        z: 50

        SequentialAnimation {
            id: tapRingAnim
            PropertyAction  { target: tapRing; property: "opacity"; value: 1.0 }
            PropertyAction  { target: tapRing; property: "scale";   value: 0.3 }
            ParallelAnimation {
                NumberAnimation { target: tapRing; property: "scale";   to: 2.0; duration: 500; easing.type: Easing.OutQuad }
                NumberAnimation { target: tapRing; property: "opacity"; to: 0;   duration: 500; easing.type: Easing.OutQuad }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  PRESS INDICATOR — bright circle at press point
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        id: pressIndicator
        width: 40; height: 40; radius: 20
        color: "#4433FF33"
        border.color: "#33FF33"
        border.width: 2
        opacity: 0
        z: 50
    }

    // ═════════════════════════════════════════════════════════════
    //  DRAG LINE — shows drag direction while holding
    // ═════════════════════════════════════════════════════════════
    Item {
        id: dragLine
        property real x1: 0
        property real y1: 0
        property real x2: 0
        property real y2: 0
        visible: false
        z: 50
        anchors.fill: parent

        // Origin circle
        Rectangle {
            x: dragLine.x1 - 10; y: dragLine.y1 - 10
            width: 20; height: 20; radius: 10
            color: "#6633FF33"
            border.color: "#33FF33"
            border.width: 2
        }

        // Direction arrow (endpoint)
        Rectangle {
            x: dragLine.x2 - 8; y: dragLine.y2 - 8
            width: 16; height: 16; radius: 8
            color: "#33FF33"
            border.color: "white"
            border.width: 2
        }

        // Line between points (using a thin rotated rectangle)
        Rectangle {
            property real dx: dragLine.x2 - dragLine.x1
            property real dy: dragLine.y2 - dragLine.y1
            property real len: Math.sqrt(dx * dx + dy * dy)
            x: dragLine.x1
            y: dragLine.y1 - 1.5
            width: len
            height: 3
            color: "#BB33FF33"
            transformOrigin: Item.Left
            rotation: Math.atan2(dy, dx) * 180 / Math.PI
        }

        // Speed label
        Text {
            x: dragLine.x2 + 12
            y: dragLine.y2 - 12
            color: "#33FF33"
            font.pixelSize: 14
            font.bold: true
            style: Text.Outline
            styleColor: "black"
            text: {
                var speed = Math.sqrt(_joyYaw * _joyYaw + _joyPitch * _joyPitch)
                return speed.toFixed(0) + " deg/s"
            }
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  TRACKING MODE OVERLAY
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        visible: _trackMode
        z: 1
        color: "transparent"
        border.color: "#33CC33"
        border.width: 4

        Text {
            anchors {
                top:                parent.top
                horizontalCenter:   parent.horizontalCenter
                topMargin:          ScreenTools.defaultFontPixelHeight * 3
            }
            text:               "TAP TARGET TO TRACK"
            color:              "#33CC33"
            font.pixelSize:     ScreenTools.defaultFontPointSize * 1.4
            font.bold:          true
            style:              Text.Outline
            styleColor:         "black"
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  STATUS HUD (bottom-right, above bottom bar)
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        id: statusHud
        z: 60
        anchors {
            right:        parent.right
            bottom:       bottomBar.top
            rightMargin:  _margin
            bottomMargin: _gap * 2
        }
        width:  hudCol.implicitWidth + _margin * 2
        height: hudCol.implicitHeight + _margin * 1.5
        radius: 6
        color:  "#AA000000"

        Column {
            id: hudCol
            anchors.centerIn: parent
            spacing: 2

            Text {
                font.family:    "monospace"
                font.pixelSize: ScreenTools.defaultFontPointSize * 0.85
                font.bold:      true
                color:          "#33FF33"
                text:           "P " + (_vl ? _vl.gimbalPitch.toFixed(1) : "0.0") + "\u00B0"
            }
            Text {
                font.family:    "monospace"
                font.pixelSize: ScreenTools.defaultFontPointSize * 0.85
                font.bold:      true
                color:          "#33FF33"
                text:           "Y " + (_vl ? _vl.gimbalYaw.toFixed(1) : "0.0") + "\u00B0"
            }
            Text {
                font.family:    "monospace"
                font.pixelSize: ScreenTools.defaultFontPointSize * 0.85
                font.bold:      true
                color:          "#33FF33"
                text:           "Z " + (_vl ? _vl.eoZoom.toFixed(1) : "1.0") + "x"
            }
            Text {
                visible:        _vl ? _vl.laserRange > 0 : false
                font.family:    "monospace"
                font.pixelSize: ScreenTools.defaultFontPointSize * 0.85
                font.bold:      true
                color:          "#33FF33"
                text:           "LR " + (_vl ? _vl.laserRange.toFixed(0) : "0") + "m"
            }
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  EXPANDED PANEL (slides up when [⋮] tapped)
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        id: expandedPanel
        z: 59
        visible: _morePanel
        anchors {
            left:           bottomBar.left
            right:          parent.right
            bottom:         bottomBar.top
            rightMargin:    _margin
            bottomMargin:   _gap * 2
        }
        height: panelCol.implicitHeight + _margin * 3
        radius: 10
        color:  "#DD000000"
        border.color: "#555"
        border.width: 1

        // Dismiss when tapping outside
        // (handled by overlay MouseArea below)

        Column {
            id: panelCol
            anchors {
                left:       parent.left
                right:      parent.right
                top:        parent.top
                margins:    _margin * 1.5
            }
            spacing: _margin

            // ── Gimbal Mode ──
            Text {
                text: "Gimbal"
                color: "#999"
                font.pixelSize: _fontSize * 0.9
                font.bold: true
            }
            Row {
                spacing: _gap
                PanelBtn {
                    label: "Follow"
                    onClicked: {
                        if (_vl) _vl.gimbalFollow()
                        _gimbalLocked = false
                    }
                }
                PanelBtn {
                    label: "Lock"
                    onClicked: {
                        if (_vl) _vl.gimbalLock()
                        _gimbalLocked = true
                    }
                }
                PanelBtn {
                    label: "Down"
                    onClicked: { if (_vl) _vl.gimbalDown() }
                }
            }

            // ── Laser ──
            Text {
                text: "Laser"
                color: "#999"
                font.pixelSize: _fontSize * 0.9
                font.bold: true
            }
            Row {
                spacing: _gap
                PanelBtn {
                    label: "Once"
                    onClicked: { if (_vl) _vl.laserRangeOnce() }
                }
                PanelBtn {
                    label: "Cont"
                    onClicked: { if (_vl) _vl.laserRangeContinuous() }
                }
                PanelBtn {
                    label: "Off"
                    onClicked: { if (_vl) _vl.laserRangeStop() }
                }
            }

            // ── Focus ──
            Text {
                text: "Focus"
                color: "#999"
                font.pixelSize: _fontSize * 0.9
                font.bold: true
            }
            Row {
                spacing: _gap
                PanelBtn {
                    label: "Auto"
                    onClicked: { if (_vl) _vl.autoFocus() }
                }
                PanelBtn {
                    label: "MF\u2212"
                    onClicked: { if (_vl) _vl.manualFocusIn() }
                }
                PanelBtn {
                    label: "MF+"
                    onClicked: { if (_vl) _vl.manualFocusOut() }
                }
            }

            // ── Camera info ──
            Text {
                text: "Camera: 192.168.144.119:2000"
                color: "#999"
                font.pixelSize: _fontSize * 0.9
                font.bold: true
            }
            Row {
                spacing: _gap
                PanelBtn {
                    label: "Reconnect"
                    wide: true
                    onClicked: {
                        if (_vl) {
                            _vl.disconnectCamera()
                            _vl.connectToCamera("192.168.144.119", 2000)
                        }
                    }
                }
            }
        }
    }

    // ── Overlay to dismiss expanded panel when tapping outside ──
    MouseArea {
        z: 58
        anchors.fill: parent
        visible: _morePanel
        onClicked: { _morePanel = false }
    }

    // ═════════════════════════════════════════════════════════════
    //  BOTTOM CONTROL BAR — grouped buttons with icons
    //
    //  ┌───────┐ ┌─────────┐ ┌──────────┐ ┌──────────────┐ ┌──┐
    //  │ −   + │ │  ⊙   ● │ │ EO  WHT  │ │  ⌂   ⊟   ◎ │ │⋮ │
    //  └───────┘ └─────────┘ └──────────┘ └──────────────┘ └──┘
    //   Zoom      Capture     Video        Gimbal           More
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        id: bottomBar
        z: 60
        anchors {
            bottom:             parent.bottom
            horizontalCenter:   parent.horizontalCenter
            bottomMargin:       ScreenTools.defaultFontPixelHeight
        }
        width:      barRow.width + _margin * 2
        height:     _btnH + _margin * 2
        radius:     height * 0.15
        color:      "#CC000000"
        border.color: "#555"
        border.width: 1

        Row {
            id: barRow
            anchors.centerIn: parent
            spacing: _gap * 1.5

            // ── Zoom group ──
            BtnGroup {
                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    VPBtn {
                        icon: "\u2212"
                        iconPx: _btnH * 0.45
                        bold: true
                        onHeldChanged: {
                            if (!_vl) return
                            if (held) _vl.zoomOut(4)
                            else      _vl.zoomStop()
                        }
                    }
                    VPBtn {
                        icon: "+"
                        iconPx: _btnH * 0.45
                        bold: true
                        onHeldChanged: {
                            if (!_vl) return
                            if (held) _vl.zoomIn(4)
                            else      _vl.zoomStop()
                        }
                    }
                }
            }

            // ── Capture group ──
            BtnGroup {
                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    VPBtn {
                        icon: "\u2299"          // ⊙ photo
                        iconPx: _btnH * 0.45
                        sub: "PHOTO"
                        onClicked: { if (_vl) _vl.takePhoto() }
                    }
                    VPBtn {
                        icon: _recording ? "\u25A0" : "\u25CF" // ■ stop / ● rec
                        iconPx: _btnH * 0.4
                        iconColor: _recording ? "#FF4444" : "white"
                        sub: _recording ? "STOP" : "REC"
                        lit: _recording
                        litColor: "#DD3333"
                        onClicked: {
                            if (!_vl) return
                            if (_recording) _vl.stopRecord()
                            else            _vl.startRecord()
                            _recording = !_recording
                        }
                    }
                }
            }

            // ── Video group ──
            BtnGroup {
                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    VPBtn {
                        icon: _sources[_srcIdx].label
                        iconPx: _fontSize * 1.1
                        sub: "SRC"
                        onClicked: {
                            if (!_vl) return
                            _srcIdx = (_srcIdx + 1) % _sources.length
                            _vl.setVideoSource(_sources[_srcIdx].id)
                        }
                    }
                    VPBtn {
                        icon: _palettes[_paletteIdx].label
                        iconPx: _fontSize * 1.1
                        sub: "PAL"
                        onClicked: {
                            if (!_vl) return
                            _paletteIdx = (_paletteIdx + 1) % _palettes.length
                            _vl.setColorPalette(_palettes[_paletteIdx].id)
                        }
                    }
                }
            }

            // ── Gimbal group ──
            BtnGroup {
                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    VPBtn {
                        icon: "\u2302"          // ⌂ home
                        iconPx: _btnH * 0.45
                        sub: "HOME"
                        onClicked: { if (_vl) _vl.gimbalHome() }
                    }
                    VPBtn {
                        icon: _gimbalLocked ? "\u25A3" : "\u25A1" // ▣ locked / □ unlocked
                        iconPx: _btnH * 0.4
                        sub: _gimbalLocked ? "LCK" : "FLW"
                        lit: _gimbalLocked
                        litColor: "#3399FF"
                        onClicked: {
                            if (!_vl) return
                            if (_gimbalLocked) {
                                _vl.gimbalFollow()
                                _gimbalLocked = false
                            } else {
                                _vl.gimbalLock()
                                _gimbalLocked = true
                            }
                        }
                    }
                    VPBtn {
                        icon: "\u25CE"          // ◎ track
                        iconPx: _btnH * 0.4
                        sub: "TRK"
                        lit: _trackMode
                        litColor: "#33CC33"
                        onClicked: {
                            if (_trackMode) {
                                if (_vl) _vl.trackStop()
                            }
                            _trackMode = !_trackMode
                        }
                    }
                }
            }

            // ── Overflow ──
            VPBtn {
                icon: "\u22EE"              // ⋮
                iconPx: _btnH * 0.45
                bold: true
                lit: _morePanel
                litColor: "#666666"
                onClicked: { _morePanel = !_morePanel }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════
    //  INLINE COMPONENTS
    // ═════════════════════════════════════════════════════════════

    // ── Button with icon + optional sub-label ──────────────────
    component VPBtn: Rectangle {
        id: _vpBtn
        property string icon:       ""
        property real   iconPx:     _fontSize
        property string iconColor:  "white"
        property string sub:        ""      // small label below icon
        property bool   bold:       false
        property bool   lit:        false
        property color  litColor:   "#DD3333"
        readonly property bool held: _vpMa.pressed

        signal clicked()

        width:  _btnW
        height: _btnH
        radius: _btnH * 0.15
        color: {
            if (lit) return _vpMa.pressed ? Qt.darker(litColor, 1.4) : litColor
            return _vpMa.pressed ? "#555" : "transparent"
        }

        Column {
            anchors.centerIn: parent
            spacing: sub ? 1 : 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           _vpBtn.icon
                color:          _vpBtn.iconColor
                font.pixelSize: _vpBtn.iconPx
                font.bold:      _vpBtn.bold || _vpBtn.lit
            }
            Text {
                visible:        _vpBtn.sub !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text:           _vpBtn.sub
                color:          "#999"
                font.pixelSize: _fontSize * 0.65
            }
        }

        MouseArea {
            id: _vpMa
            anchors.fill: parent
            onClicked: _vpBtn.clicked()
        }
    }

    // ── Group background for related buttons ───────────────────
    component BtnGroup: Rectangle {
        default property alias content: _groupContent.data

        width:  _groupContent.childrenRect.width + 6
        height: _btnH
        radius: _btnH * 0.15
        color:  "#33FFFFFF"     // subtle group tint

        Item {
            id: _groupContent
            anchors.fill: parent
        }
    }

    // ── Button for expanded panel ──────────────────────────────
    component PanelBtn: Rectangle {
        id: _panelBtn
        property string label:  ""
        property bool   wide:   false

        signal clicked()

        width:  wide ? _btnW * 2.2 : _btnW * 1.5
        height: _btnH * 0.85
        radius: _btnH * 0.12
        color:  _panelMa.pressed ? "#555" : "#333"
        border.color: "#666"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text:           _panelBtn.label
            color:          "white"
            font.pixelSize: _fontSize
        }

        MouseArea {
            id: _panelMa
            anchors.fill: parent
            onClicked: _panelBtn.clicked()
        }
    }
}
