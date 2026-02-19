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
// Bottom bar: Zoom, Photo, Record, Source, AF, Home, Track
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
    property bool _recording:   false
    property int  _srcIdx:      0
    property bool _trackMode:   false
    property real _joyPitch:    0
    property real _joyYaw:      0
    property bool _dragging:    false
    property int  _touchCount:  0

    // ── Camera source table ──────────────────────────────────────
    readonly property var _sources: [
        { id: 0, label: "EO"   },
        { id: 1, label: "IR"   },
        { id: 2, label: "PIP"  },
        { id: 3, label: "PIP2" }
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
            text: "v1.12"
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
    //  BOTTOM CONTROL BAR
    // ═════════════════════════════════════════════════════════════
    Rectangle {
        id: bottomBar
        z: 60
        anchors {
            bottom:             parent.bottom
            horizontalCenter:   parent.horizontalCenter
            bottomMargin:       ScreenTools.defaultFontPixelHeight
        }
        width:      barRow.implicitWidth + _margin * 3
        height:     _btnH + _margin * 2
        radius:     height * 0.15
        color:      "#CC000000"
        border.color: "#555"
        border.width: 1

        RowLayout {
            id: barRow
            anchors.centerIn: parent
            spacing: _gap

            // ── Zoom ──
            VPBtn {
                label: "\u2212"
                fontPx: _btnH * 0.5
                bold: true
                onHeldChanged: {
                    if (!_vl) return
                    if (held) _vl.zoomOut(4)
                    else      _vl.zoomStop()
                }
            }
            VPBtn {
                label: "+"
                fontPx: _btnH * 0.5
                bold: true
                onHeldChanged: {
                    if (!_vl) return
                    if (held) _vl.zoomIn(4)
                    else      _vl.zoomStop()
                }
            }

            BarSep {}

            // ── Capture ──
            VPBtn {
                label: "PHOTO"
                onClicked: { if (_vl) _vl.takePhoto() }
            }
            VPBtn {
                label: _recording ? "STOP" : "REC"
                lit: _recording
                litColor: "#DD3333"
                onClicked: {
                    if (!_vl) return
                    if (_recording) _vl.stopRecord()
                    else            _vl.startRecord()
                    _recording = !_recording
                }
            }

            BarSep {}

            // ── Camera source & focus ──
            VPBtn {
                label: _sources[_srcIdx].label
                fontPx: _fontSize * 1.1
                onClicked: {
                    if (!_vl) return
                    _srcIdx = (_srcIdx + 1) % _sources.length
                    _vl.setVideoSource(_sources[_srcIdx].id)
                }
            }
            VPBtn {
                label: "AF"
                fontPx: _fontSize * 1.1
                onClicked: { if (_vl) _vl.autoFocus() }
            }

            BarSep {}

            // ── Gimbal & tracking ──
            VPBtn {
                label: "HOME"
                onClicked: { if (_vl) _vl.gimbalHome() }
            }
            VPBtn {
                label: "TRK"
                fontPx: _fontSize * 1.1
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

    // ═════════════════════════════════════════════════════════════
    //  INLINE COMPONENTS
    // ═════════════════════════════════════════════════════════════

    component VPBtn: Rectangle {
        id: _vpBtn
        property string label:      ""
        property real   fontPx:     _fontSize
        property bool   bold:       false
        property bool   lit:        false
        property color  litColor:   "#DD3333"
        readonly property bool held: _vpMa.pressed

        signal clicked()

        Layout.preferredWidth:  _btnW
        Layout.preferredHeight: _btnH
        radius: _btnH * 0.15
        color: {
            if (lit) return _vpMa.pressed ? Qt.darker(litColor, 1.4) : litColor
            return _vpMa.pressed ? "#555" : "#222"
        }
        border.color: lit ? Qt.lighter(litColor, 1.3) : "#555"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text:           _vpBtn.label
            color:          "white"
            font.pixelSize: _vpBtn.fontPx
            font.bold:      _vpBtn.bold || _vpBtn.lit
        }

        MouseArea {
            id: _vpMa
            anchors.fill: parent
            onClicked: _vpBtn.clicked()
        }
    }

    component BarSep: Rectangle {
        Layout.preferredWidth:  1
        Layout.preferredHeight: _btnH * 0.6
        Layout.alignment:       Qt.AlignVCenter
        color: "#555"
    }
}
