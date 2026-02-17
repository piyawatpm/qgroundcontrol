import QtQuick

import QGroundControl
import QGroundControl.Controls

Item {
    id: _root

    property Item pipView
    property Item pipState: videoPipState

    property int    _track_rec_x:       0
    property int    _track_rec_y:       0

    // Gimbal/focus gesture state
    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property var    _gimbalController:  _activeVehicle ? _activeVehicle.gimbalController : null
    property var    _activeGimbal:      _gimbalController ? _gimbalController.activeGimbal : null
    property bool   _hasGimbal:         _activeGimbal !== undefined && _activeGimbal !== null
    property real   _pressStartX:       0
    property real   _pressStartY:       0
    property bool   _holdDetected:      false
    property bool   _isGimbalDragging:  false
    property real   _dragDx:            0
    property real   _dragDy:            0
    property real   _dragAngle:         0       // degrees, 0=right, 90=down
    property real   _dragDist:          0       // pixel distance from press point

    PipState {
        id:         videoPipState
        pipView:    _root.pipView
        isDark:     true

        onWindowAboutToOpen: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onWindowAboutToClose: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onStateChanged: {
            if (pipState.state !== pipState.fullState) {
                QGroundControl.videoManager.fullScreen = false
            }
        }
    }

    Timer {
        id:           videoStartDelay
        interval:     2000;
        running:      false
        repeat:       false
        onTriggered:  QGroundControl.videoManager.startVideo()
    }

    // Hold detection timer (250ms to distinguish tap from hold)
    Timer {
        id:         holdDetectTimer
        interval:   250
        onTriggered: {
            _holdDetected = true
        }
    }

    // Gimbal repeat timer during drag
    Timer {
        id:         gimbalDragTimer
        interval:   100
        repeat:     true
        onTriggered: {
            if (_isGimbalDragging) {
                _gimbalStep(_dragDx, _dragDy)
            }
        }
    }

    // Focus square hide timer
    Timer {
        id:         focusHideTimer
        interval:   800
        onTriggered: focusSquare.visible = false
    }

    // Mock video placeholder (shown when no real video source is active)
    Rectangle {
        id:             mockVideoView
        anchors.fill:   parent
        color:          "#1a1a2e"
        visible:        !QGroundControl.videoManager.isStreamSource && !QGroundControl.videoManager.isUvc

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#16213e" }
                GradientStop { position: 0.5; color: "#0f3460" }
                GradientStop { position: 1.0; color: "#1a1a2e" }
            }
        }

        // Scan line animation
        Rectangle {
            width: parent.width
            height: 2
            color: Qt.rgba(0.2, 0.8, 0.2, 0.3)
            y: 0
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: mockVideoView.height; duration: 3000; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0; duration: 3000; easing.type: Easing.InOutQuad }
            }
        }

        // Crosshair overlay
        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.3
            height: width
            Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.3) }
            Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1,1,1,0.3) }
            Rectangle { anchors.centerIn: parent; width: parent.width * 0.15; height: parent.width * 0.15; color: "transparent"; border.color: Qt.rgba(1,1,1,0.4); border.width: 1 }
        }

        Column {
            anchors.centerIn: parent
            spacing: ScreenTools.defaultFontPixelHeight * 0.5
            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           qsTr("MOCK VIDEO")
                font.pointSize: _root.pipState.state === _root.pipState.fullState ? ScreenTools.largeFontPointSize : ScreenTools.defaultFontPointSize
                font.bold:      true
                color:          "white"
            }
            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           qsTr("Camera feed will appear here")
                font.pointSize: ScreenTools.defaultFontPointSize
                color:          Qt.rgba(1,1,1,0.6)
                visible:        _root.pipState.state === _root.pipState.fullState
            }
        }
    }

    //-- Video Streaming
    FlightDisplayViewVideo {
        id:             videoStreaming
        anchors.fill:   parent
        useSmallFont:   _root.pipState.state !== _root.pipState.fullState
        visible:        QGroundControl.videoManager.isStreamSource
    }
    //-- UVC Video (USB Camera or Video Device)
    Loader {
        id:             cameraLoader
        anchors.fill:   parent
        visible:        QGroundControl.videoManager.isUvc
        source:         QGroundControl.videoManager.uvcEnabled ? "qrc:/qml/QGroundControl/FlyView/FlightDisplayViewUVC.qml" : "qrc:/qml/QGroundControl/FlyView//FlightDisplayViewDummy.qml"
    }

    QGCLabel {
        text: qsTr("Double-click to exit full screen")
        font.pointSize: ScreenTools.largeFontPointSize
        visible: QGroundControl.videoManager.fullScreen && flyViewVideoMouseArea.containsMouse
        anchors.centerIn: parent

        onVisibleChanged: {
            if (visible) {
                labelAnimation.start()
            }
        }

        PropertyAnimation on opacity {
            id: labelAnimation
            duration: 10000
            from: 1.0
            to: 0.0
            easing.type: Easing.InExpo
        }
    }

    // ═══════════════════════════════════════
    // FOCUS SQUARE (shown on tap)
    // ═══════════════════════════════════════
    Rectangle {
        id:             focusSquare
        width:          ScreenTools.defaultFontPixelHeight * 4
        height:         width
        color:          "transparent"
        border.color:   Qt.rgba(0.2, 1.0, 0.2, 0.9)
        border.width:   2
        visible:        false
        z:              50

        // Corner brackets
        Rectangle { width: parent.width * 0.2; height: 2; color: parent.border.color; anchors.top: parent.top; anchors.left: parent.left }
        Rectangle { width: 2; height: parent.height * 0.2; color: parent.border.color; anchors.top: parent.top; anchors.left: parent.left }
        Rectangle { width: parent.width * 0.2; height: 2; color: parent.border.color; anchors.top: parent.top; anchors.right: parent.right }
        Rectangle { width: 2; height: parent.height * 0.2; color: parent.border.color; anchors.top: parent.top; anchors.right: parent.right }
        Rectangle { width: parent.width * 0.2; height: 2; color: parent.border.color; anchors.bottom: parent.bottom; anchors.left: parent.left }
        Rectangle { width: 2; height: parent.height * 0.2; color: parent.border.color; anchors.bottom: parent.bottom; anchors.left: parent.left }
        Rectangle { width: parent.width * 0.2; height: 2; color: parent.border.color; anchors.bottom: parent.bottom; anchors.right: parent.right }
        Rectangle { width: 2; height: parent.height * 0.2; color: parent.border.color; anchors.bottom: parent.bottom; anchors.right: parent.right }

        // Scale animation
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // ═══════════════════════════════════════
    // GIMBAL DRAG INDICATOR (shown on hold+drag)
    // ═══════════════════════════════════════
    Item {
        id:         gimbalDragIndicator
        anchors.fill: parent
        visible:    _isGimbalDragging
        z:          50

        // Touch point ring (origin)
        Rectangle {
            x:              _pressStartX - width / 2
            y:              _pressStartY - height / 2
            width:          ScreenTools.defaultFontPixelHeight * 2.5
            height:         width
            radius:         width / 2
            color:          Qt.rgba(0, 0, 0, 0.3)
            border.width:   2
            border.color:   Qt.rgba(0.2, 1.0, 0.2, 0.5)
        }

        // Direction line from press point toward drag
        Rectangle {
            x:              _pressStartX
            y:              _pressStartY - height / 2
            width:          Math.min(_dragDist, ScreenTools.defaultFontPixelHeight * 4)
            height:         2
            color:          Qt.rgba(0.2, 1.0, 0.2, 0.7)
            transformOrigin: Item.Left
            rotation:       _dragAngle
        }

        // Arrow head (triangle rotated to drag angle via rotation)
        Item {
            x:              _pressStartX
            y:              _pressStartY
            rotation:       _dragAngle

            // Simple arrowhead using rotated rectangle (avoids expensive Canvas onPaint)
            Rectangle {
                x:      Math.min(_dragDist, ScreenTools.defaultFontPixelHeight * 4) - 6
                y:      -6
                width:  12
                height: 12
                color:  Qt.rgba(0.2, 1.0, 0.2, 0.9)
                rotation: 45
                antialiasing: true
            }
        }
    }

    OnScreenGimbalController {
        id:                      onScreenGimbalController
        anchors.fill:            parent
        screenX:                 flyViewVideoMouseArea.mouseX
        screenY:                 flyViewVideoMouseArea.mouseY
        cameraTrackingEnabled:   videoStreaming._camera && videoStreaming._camera.trackingEnabled
    }

    MouseArea {
        id:                         flyViewVideoMouseArea
        anchors.fill:               parent
        enabled:                    pipState.state === pipState.fullState
        hoverEnabled:               true

        property double x0:         0
        property double x1:         0
        property double y0:         0
        property double y1:         0
        property double offset_x:   0
        property double offset_y:   0
        property double radius:     20
        property var trackingROI:   null
        property var trackingStatus: trackingStatusComponent.createObject(flyViewVideoMouseArea, {})

        onDoubleClicked: QGroundControl.videoManager.fullScreen = !QGroundControl.videoManager.fullScreen

        onPressed:(mouse) => {
            onScreenGimbalController.pressControl()

            // Record press point for gesture detection
            _pressStartX = mouse.x
            _pressStartY = mouse.y
            _holdDetected = false
            _isGimbalDragging = false
            _dragDist = 0
            _dragAngle = 0

            _track_rec_x = mouse.x
            _track_rec_y = mouse.y

            // Start hold detection
            holdDetectTimer.start()

            // Tracking ROI (only when tracking enabled)
            if(videoStreaming._camera) {
                if (videoStreaming._camera.trackingEnabled) {
                    holdDetectTimer.stop()  // Don't do gimbal when tracking
                    trackingROI = trackingROIComponent.createObject(flyViewVideoMouseArea, {
                        "x": mouse.x,
                        "y": mouse.y
                    });
                }
            }
        }

        onPositionChanged: (mouse) => {
            // Tracking ROI drag
            if (trackingROI !== null) {
                if (mouse.x < trackingROI.x) {
                    trackingROI.x = mouse.x
                    trackingROI.width = Math.abs(mouse.x - _track_rec_x)
                } else {
                    trackingROI.width = Math.abs(mouse.x - trackingROI.x)
                }
                if (mouse.y < trackingROI.y) {
                    trackingROI.y = mouse.y
                    trackingROI.height = Math.abs(mouse.y - _track_rec_y)
                } else {
                    trackingROI.height = Math.abs(mouse.y - trackingROI.y)
                }
                return
            }

            // Gimbal drag (only after hold detected)
            if (_holdDetected) {
                var dx = mouse.x - _pressStartX
                var dy = mouse.y - _pressStartY
                var dist = Math.sqrt(dx * dx + dy * dy)

                if (dist > 15) {
                    // Normalize direction, scale speed by distance
                    var ndx = dx / dist
                    var ndy = -dy / dist  // Invert Y: drag up = pitch up
                    var speed = Math.min(dist / 100, 1.0)  // 0..1 speed factor

                    _dragDx = ndx * speed
                    _dragDy = ndy * speed
                    _dragDist = dist
                    _dragAngle = Math.atan2(dy, dx) * 180 / Math.PI  // degrees, 0=right

                    if (!_isGimbalDragging) {
                        _isGimbalDragging = true
                        _gimbalStep(_dragDx, _dragDy)
                        gimbalDragTimer.start()
                    }
                }
            }
        }

        onReleased: (mouse) => {
            onScreenGimbalController.releaseControl()
            holdDetectTimer.stop()

            // Stop gimbal drag
            if (_isGimbalDragging) {
                gimbalDragTimer.stop()
                _isGimbalDragging = false
                _dragDist = 0
                _dragAngle = 0
            }

            // TAP detection: short press, small movement, no tracking
            var dx = mouse.x - _pressStartX
            var dy = mouse.y - _pressStartY
            var moved = Math.sqrt(dx * dx + dy * dy)

            if (!_holdDetected && moved < 15 && trackingROI === null) {
                _showFocusSquare(mouse.x, mouse.y)
                _autoFocus()
            }

            // Tracking ROI release
            if (trackingROI !== null) {
                trackingROI.destroy();
            }

            if(videoStreaming._camera) {
                if (videoStreaming._camera.trackingEnabled) {
                    x0 = Math.min(_track_rec_x, mouse.x)
                    x1 = Math.max(_track_rec_x, mouse.x)
                    y0 = Math.min(_track_rec_y, mouse.y)
                    y1 = Math.max(_track_rec_y, mouse.y)

                    offset_x = (parent.width - videoStreaming.getWidth()) / 2
                    offset_y = (parent.height - videoStreaming.getHeight()) / 2

                    x0 = x0 - offset_x
                    x1 = x1 - offset_x
                    y0 = y0 - offset_y
                    y1 = y1 - offset_y

                    x0 = Math.max(Math.min(x0 / videoStreaming.getWidth(), 1.0), 0.0)
                    x1 = Math.max(Math.min(x1 / videoStreaming.getWidth(), 1.0), 0.0)
                    y0 = Math.max(Math.min(y0 / videoStreaming.getHeight(), 1.0), 0.0)
                    y1 = Math.max(Math.min(y1 / videoStreaming.getHeight(), 1.0), 0.0)

                    if (Math.abs(_track_rec_x - mouse.x) < 10 && Math.abs(_track_rec_y - mouse.y) < 10) {
                        var pt  = Qt.point(x0, y0)
                        videoStreaming._camera.startTracking(pt, radius / videoStreaming.getWidth())
                    } else {
                        var rec = Qt.rect(x0, y0, x1 - x0, y1 - y0)
                        videoStreaming._camera.startTracking(rec)
                    }
                    _track_rec_x = 0
                    _track_rec_y = 0
                }
            }

            _holdDetected = false
        }

        onClicked: {
            // Only fire gimbal click if it wasn't a tap-focus or drag
            if (_holdDetected || _isGimbalDragging) {
                return
            }
            onScreenGimbalController.clickControl()
        }

        Component {
            id: trackingROIComponent

            Rectangle {
                color:              Qt.rgba(0.1,0.85,0.1,0.25)
                border.color:       "green"
                border.width:       1
            }
        }

        Component {
            id: trackingStatusComponent

            Rectangle {
                color:              "transparent"
                border.color:       "red"
                border.width:       5
                radius:             5
            }
        }

        Timer {
            id: trackingStatusTimer
            interval:               50
            repeat:                 true
            running:                videoStreaming._camera && videoStreaming._camera.trackingEnabled
            onTriggered: {
                if (videoStreaming._camera) {
                    if (videoStreaming._camera.trackingEnabled && videoStreaming._camera.trackingImageStatus) {
                        var margin_hor = (parent.parent.width - videoStreaming.getWidth()) / 2
                        var margin_ver = (parent.parent.height - videoStreaming.getHeight()) / 2
                        var left = margin_hor + videoStreaming.getWidth() * videoStreaming._camera.trackingImageRect.left
                        var top = margin_ver + videoStreaming.getHeight() * videoStreaming._camera.trackingImageRect.top
                        var right = margin_hor + videoStreaming.getWidth() * videoStreaming._camera.trackingImageRect.right
                        var bottom = margin_ver + !isNaN(videoStreaming._camera.trackingImageRect.bottom) ? videoStreaming.getHeight() * videoStreaming._camera.trackingImageRect.bottom : top + (right - left)
                        var width = right - left
                        var height = bottom - top

                        flyViewVideoMouseArea.trackingStatus.x = left
                        flyViewVideoMouseArea.trackingStatus.y = top
                        flyViewVideoMouseArea.trackingStatus.width = width
                        flyViewVideoMouseArea.trackingStatus.height = height
                    } else {
                        flyViewVideoMouseArea.trackingStatus.x = 0
                        flyViewVideoMouseArea.trackingStatus.y = 0
                        flyViewVideoMouseArea.trackingStatus.width = 0
                        flyViewVideoMouseArea.trackingStatus.height = 0
                    }
                }
            }
        }
    }

    ProximityRadarVideoView{
        anchors.fill:   parent
        vehicle:        QGroundControl.multiVehicleManager.activeVehicle
    }

    ObstacleDistanceOverlayVideo {
        id: obstacleDistance
        showText: pipState.state === pipState.fullState
    }

    // ═══════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════

    function _showFocusSquare(mx, my) {
        focusSquare.x = mx - focusSquare.width / 2
        focusSquare.y = my - focusSquare.height / 2
        focusSquare.scale = 1.4
        focusSquare.opacity = 1.0
        focusSquare.visible = true
        focusSquare.scale = 1.0  // Triggers behavior animation
        focusHideTimer.restart()
    }

    function _autoFocus() {
        if (_activeVehicle) {
            var camera = videoStreaming._camera
            var compId = camera ? camera.compID : 1
            // MAV_CMD_SET_CAMERA_FOCUS (532), param1=4 (FOCUS_TYPE_AUTO)
            _activeVehicle.sendCommand(compId, 532, false, 4, 0)
        }
    }

    function _gimbalStep(dx, dy) {
        if (_hasGimbal) {
            _gimbalController.gimbalOnScreenControl(dx, dy, true, false, false)
        } else if (_activeVehicle) {
            var pitchInc = dy * 15   // degrees per step
            var yawInc   = dx * 15
            // flags: ROLL_LOCK(4) | PITCH_LOCK(8) | YAW_IN_VEHICLE_FRAME(32) = 44
            _activeVehicle.sendCommand(1, 287, false, pitchInc, yawInc, NaN, NaN, 44, 0, 0)
        }
    }
}
