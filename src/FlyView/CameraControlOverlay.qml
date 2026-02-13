import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import QGroundControl
import QGroundControl.Controls

Item {
    id: _root

    // Real camera bindings (null when no vehicle/camera connected)
    property var  _activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle
    property var  _cameraManager:    _activeVehicle ? _activeVehicle.cameraManager : null
    property var  _camera:           _cameraManager ? _cameraManager.currentCameraInstance : null
    property bool _hasRealCamera:    _camera !== null
    property var  _gimbalController: _activeVehicle ? _activeVehicle.gimbalController : null
    property var  _activeGimbal:     _gimbalController ? _gimbalController.activeGimbal : null
    property bool _hasGimbal:        _activeGimbal !== undefined && _activeGimbal !== null

    // Video settings
    property var  _videoSettings:   QGroundControl.settingsManager.videoSettings

    // Mock state for when no real camera is connected
    property bool _isMockPhotoMode:     true
    property real _mockZoomLevel:       0
    property real _mockGimbalPitch:     0
    property real _mockGimbalYaw:       0
    property bool _mockRecording:       false
    property int  _mockRecordSeconds:   0
    property int  _mockPhotoCount:      0
    property real _mockFocusLevel:      0
    property int  _mockLensMode:        0   // 0=Wide, 1=Zoom, 2=Thermal
    property bool _mockTrackingEnabled: false

    // Derived state — adapts to real or mock
    property bool _isPhotoMode:     _hasRealCamera ? (_camera.cameraMode === MavlinkCameraControl.CAM_MODE_PHOTO) : _isMockPhotoMode
    property bool _isVideoMode:     !_isPhotoMode
    property real _zoomLevel:       _hasRealCamera ? _camera.zoomLevel : _mockZoomLevel
    property bool _isRecording:     _hasRealCamera ? (_camera.videoCaptureStatus === MavlinkCameraControl.VIDEO_CAPTURE_STATUS_RUNNING) : _mockRecording
    property bool _isShooting:      _hasRealCamera ? (_camera.photoCaptureStatus === MavlinkCameraControl.PHOTO_CAPTURE_IN_PROGRESS) : false

    // Derived focus/lens/tracking state
    property real _focusLevel:      _hasRealCamera ? (_camera.focusLevel || 0) : _mockFocusLevel
    property int  _lensMode:        _mockLensMode
    property bool _trackingEnabled: _hasRealCamera ? (_camera.trackingEnabled || false) : _mockTrackingEnabled

    // B&W filter toggle (exposed to parent)
    property bool bwFilterEnabled:  false

    // RTSP settings popup
    property bool _rtspPopupVisible: false

    // Panel collapse
    property bool _collapsed:       false

    // Adaptive sizing for small screens
    property bool   _isSmallScreen:     ScreenTools.isTinyScreen || ScreenTools.isShortScreen
    property bool   _isMobileScreen:    ScreenTools.isMobile
    property real   _scaleFactor:       _isSmallScreen ? 0.7 : (_isMobileScreen ? 0.85 : 1.0)
    property real   _panelWidth:        ScreenTools.defaultFontPixelWidth * 7 * _scaleFactor
    property real   _buttonSize:        Math.max(ScreenTools.defaultFontPixelHeight * 2.2 * _scaleFactor, ScreenTools.minTouchPixels)
    property real   _smallButtonSize:   Math.max(ScreenTools.defaultFontPixelHeight * 1.6 * _scaleFactor, ScreenTools.minTouchPixels * 0.8)
    property real   _margins:           ScreenTools.defaultFontPixelWidth * 0.5
    property real   _spacing:           ScreenTools.defaultFontPixelHeight * 0.3 * _scaleFactor
    property real   _sectionSpacing:    ScreenTools.defaultFontPixelHeight * 0.15
    property real   _zoomBarHeight:     ScreenTools.defaultFontPixelHeight * 3 * _scaleFactor
    property real   _gimbalPadSize:     _panelWidth - (_margins * 2)

    QGCPalette { id: qgcPal; colorGroupEnabled: enabled }

    // Mock record timer
    Timer {
        id:         mockRecordTimer
        interval:   1000
        repeat:     true
        running:    !_hasRealCamera && _mockRecording
        onTriggered: _mockRecordSeconds++
    }

    // Mock photo flash reset
    Timer {
        id:         mockPhotoFlashTimer
        interval:   300
        onTriggered: photoFlash.opacity = 0
    }

    // AF feedback flash reset
    Timer {
        id:         afFlashTimer
        interval:   400
        onTriggered: afFlashRect.opacity = 0
    }

    // Collapse/Expand toggle button (always visible)
    Rectangle {
        id:                     collapseButton
        anchors.right:          parent.right
        anchors.top:            parent.top
        width:                  Math.max(ScreenTools.defaultFontPixelWidth * 2.5, ScreenTools.minTouchPixels)
        height:                 width
        radius:                 ScreenTools.defaultFontPixelWidth * 0.5
        color:                  Qt.rgba(qgcPal.window.r, qgcPal.window.g, qgcPal.window.b, 0.75)
        z:                      1

        QGCLabel {
            anchors.centerIn:   parent
            text:               _collapsed ? "<" : ">"
            font.bold:          true
            font.pointSize:     ScreenTools.smallFontPointSize
            color:              qgcPal.text
        }

        MouseArea {
            anchors.fill:   parent
            onClicked:      _collapsed = !_collapsed
        }
    }

    // Main panel with Flickable for small screens
    Rectangle {
        id:                     mainPanel
        anchors.right:          parent.right
        anchors.top:            collapseButton.bottom
        anchors.topMargin:      _margins
        anchors.bottom:         parent.bottom
        width:                  _panelWidth + (_margins * 2)
        radius:                 ScreenTools.defaultFontPixelWidth * 0.5
        color:                  Qt.rgba(qgcPal.window.r, qgcPal.window.g, qgcPal.window.b, 0.85)
        visible:                !_collapsed
        clip:                   true

        DeadMouseArea { anchors.fill: parent }

        Flickable {
            id:                     flickable
            anchors.fill:           parent
            anchors.margins:        _margins
            contentWidth:           panelColumn.width
            contentHeight:          panelColumn.height
            flickableDirection:     Flickable.VerticalFlick
            boundsBehavior:         Flickable.StopAtBounds

            Column {
                id:                     panelColumn
                width:                  _panelWidth
                spacing:                _spacing

                // ═══════════════════════════════════════
                // CAPTURE BUTTON (moved to top for quick access)
                // ═══════════════════════════════════════
                Column {
                    width:      parent.width
                    spacing:    _sectionSpacing

                    // Photo/Video mode toggle (compact pill)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:              _panelWidth - (_margins * 2)
                        height:             _smallButtonSize
                        color:              qgcPal.windowShadeLight
                        radius:             height * 0.5

                        // Video Mode
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:           parent.left
                            width:                  parent.height
                            height:                 parent.height
                            radius:                 height * 0.5
                            color:                  _isVideoMode ? qgcPal.window : qgcPal.windowShadeLight
                            border.color:           qgcPal.text
                            border.width:           _isVideoMode ? 1 : 0

                            QGCColoredImage {
                                height:             parent.height * 0.5
                                width:              height
                                anchors.centerIn:   parent
                                source:             "/qmlimages/camera_video.svg"
                                fillMode:           Image.PreserveAspectFit
                                sourceSize.height:  height
                                color:              _isVideoMode ? qgcPal.colorGreen : qgcPal.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (_hasRealCamera) {
                                        _camera.setCameraModeVideo()
                                    } else {
                                        _isMockPhotoMode = false
                                    }
                                }
                            }
                        }

                        // Photo Mode
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right:          parent.right
                            width:                  parent.height
                            height:                 parent.height
                            radius:                 height * 0.5
                            color:                  _isPhotoMode ? qgcPal.window : qgcPal.windowShadeLight
                            border.color:           qgcPal.text
                            border.width:           _isPhotoMode ? 1 : 0

                            QGCColoredImage {
                                height:             parent.height * 0.5
                                width:              height
                                anchors.centerIn:   parent
                                source:             "/qmlimages/camera_photo.svg"
                                fillMode:           Image.PreserveAspectFit
                                sourceSize.height:  height
                                color:              _isPhotoMode ? qgcPal.colorGreen : qgcPal.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (_hasRealCamera) {
                                        _camera.setCameraModePhoto()
                                    } else {
                                        _isMockPhotoMode = true
                                    }
                                }
                            }
                        }
                    }

                    // Capture button
                    Rectangle {
                        id:                     captureBtn
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  _buttonSize
                        height:                 _buttonSize
                        radius:                 _buttonSize * 0.5
                        color:                  qgcPal.button
                        border.width:           2
                        border.color:           qgcPal.buttonText

                        property color _captureColor: _isPhotoMode ? "white" : "#e74c3c"

                        Rectangle {
                            anchors.centerIn:           parent
                            anchors.alignWhenCentered:  false
                            width:                      parent.width * 0.75
                            height:                     width
                            radius:                     width * 0.5
                            color:                      qgcPal.buttonText
                        }

                        Rectangle {
                            anchors.centerIn:           parent
                            anchors.alignWhenCentered:  false
                            width:                      _isRecording ? parent.width * 0.35 : parent.width * 0.65
                            height:                     width
                            radius:                     _isRecording ? ScreenTools.defaultFontPixelWidth * 0.3 : width * 0.5
                            color:                      captureBtn._captureColor

                            Behavior on width { NumberAnimation { duration: 150 } }
                            Behavior on radius { NumberAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked:    _root._triggerCapture()
                        }
                    }

                    // Record time / photo count
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  statusLabel.width + (_margins * 2)
                        height:                 statusLabel.height + (_margins * 0.5)
                        radius:                 ScreenTools.defaultFontPixelWidth * 0.3
                        color:                  _isRecording ? Qt.rgba(0.9, 0.2, 0.2, 0.7) : "transparent"

                        QGCLabel {
                            id:                 statusLabel
                            anchors.centerIn:   parent
                            font.pointSize:     ScreenTools.smallFontPointSize
                            color:              qgcPal.text
                            text: {
                                if (_isVideoMode) {
                                    if (_hasRealCamera) {
                                        return _isRecording ? _camera.recordTimeStr : "00:00:00"
                                    } else {
                                        return _formatTime(_mockRecordSeconds)
                                    }
                                } else {
                                    if (_hasRealCamera && _activeVehicle) {
                                        return ('00000' + _activeVehicle.cameraTriggerPoints.count).slice(-5)
                                    } else {
                                        return ('00000' + _mockPhotoCount).slice(-5)
                                    }
                                }
                            }
                        }
                    }

                    // Storage status
                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pointSize:     ScreenTools.smallFontPointSize
                        color:              qgcPal.text
                        text:               _hasRealCamera ? "SD: " + _camera.storageFreeStr : ""
                        visible:            _hasRealCamera && _camera.storageStatus === MavlinkCameraControl.STORAGE_READY
                    }
                }

                // Separator
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3) }

                // ═══════════════════════════════════════
                // ZOOM SECTION
                // ═══════════════════════════════════════
                Column {
                    width:      parent.width
                    spacing:    _sectionSpacing

                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               qsTr("ZOOM")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                        color:              qgcPal.text
                    }

                    // Zoom In button
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  _smallButtonSize
                        height:                 _smallButtonSize
                        radius:                 _smallButtonSize * 0.5
                        color:                  zoomInMA.pressed ? qgcPal.buttonHighlight : qgcPal.button
                        border.width:           1
                        border.color:           qgcPal.buttonText

                        QGCLabel {
                            anchors.centerIn:   parent
                            text:               "+"
                            font.pointSize:     ScreenTools.largeFontPointSize
                            font.bold:          true
                            color:              qgcPal.buttonText
                        }

                        MouseArea {
                            id:             zoomInMA
                            anchors.fill:   parent
                            onClicked:      _root._zoomStep(1)
                        }
                    }

                    // Zoom level indicator
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  ScreenTools.defaultFontPixelWidth * 1.5
                        height:                 _zoomBarHeight
                        radius:                 width * 0.5
                        color:                  Qt.rgba(qgcPal.windowShadeLight.r, qgcPal.windowShadeLight.g, qgcPal.windowShadeLight.b, 0.5)

                        Rectangle {
                            anchors.bottom:     parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width:              parent.width
                            height:             parent.height * (_zoomLevel / 100)
                            radius:             width * 0.5
                            color:              qgcPal.colorGreen
                        }
                    }

                    // Zoom label
                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               Math.round(_zoomLevel) + "%"
                        font.pointSize:     ScreenTools.smallFontPointSize
                        color:              qgcPal.text
                    }

                    // Zoom Out button
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  _smallButtonSize
                        height:                 _smallButtonSize
                        radius:                 _smallButtonSize * 0.5
                        color:                  zoomOutMA.pressed ? qgcPal.buttonHighlight : qgcPal.button
                        border.width:           1
                        border.color:           qgcPal.buttonText

                        QGCLabel {
                            anchors.centerIn:   parent
                            text:               "-"
                            font.pointSize:     ScreenTools.largeFontPointSize
                            font.bold:          true
                            color:              qgcPal.buttonText
                        }

                        MouseArea {
                            id:             zoomOutMA
                            anchors.fill:   parent
                            onClicked:      _root._zoomStep(-1)
                        }
                    }
                }

                // Separator
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3) }

                // ═══════════════════════════════════════
                // FOCUS SECTION
                // ═══════════════════════════════════════
                Column {
                    width:      parent.width
                    spacing:    _sectionSpacing
                    visible:    !_hasRealCamera || (_camera && _camera.hasFocus)

                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               qsTr("FOCUS")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                        color:              qgcPal.text
                    }

                    // AF (Auto Focus) button
                    Rectangle {
                        id:                     afButton
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  _smallButtonSize * 1.3
                        height:                 _smallButtonSize * 0.65
                        radius:                 ScreenTools.defaultFontPixelWidth * 0.3
                        color:                  afMA.pressed ? qgcPal.buttonHighlight : qgcPal.button
                        border.width:           1
                        border.color:           qgcPal.buttonText

                        // AF flash overlay
                        Rectangle {
                            id:             afFlashRect
                            anchors.fill:   parent
                            radius:         parent.radius
                            color:          qgcPal.colorGreen
                            opacity:        0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        QGCLabel {
                            anchors.centerIn:   parent
                            text:               qsTr("AF")
                            font.pointSize:     ScreenTools.smallFontPointSize
                            font.bold:          true
                            color:              qgcPal.buttonText
                        }

                        MouseArea {
                            id:             afMA
                            anchors.fill:   parent
                            onClicked: {
                                if (_hasRealCamera && _activeVehicle) {
                                    // MAV_CMD_SET_CAMERA_FOCUS (532), param1=4 (FOCUS_TYPE_AUTO)
                                    _activeVehicle.sendCommand(_camera.compID, 532, false, 4, 0)
                                }
                                // Visual feedback flash
                                afFlashRect.opacity = 0.6
                                afFlashTimer.start()
                            }
                        }
                    }

                    // MF (Manual Focus) slider
                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               qsTr("MF")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        color:              qgcPal.text
                    }

                    // Focus level bar (vertical slider)
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  ScreenTools.defaultFontPixelWidth * 3
                        height:                 _zoomBarHeight

                        Rectangle {
                            anchors.centerIn:   parent
                            width:              ScreenTools.defaultFontPixelWidth * 1.5
                            height:             parent.height
                            radius:             width * 0.5
                            color:              Qt.rgba(qgcPal.windowShadeLight.r, qgcPal.windowShadeLight.g, qgcPal.windowShadeLight.b, 0.5)

                            Rectangle {
                                anchors.bottom:     parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width:              parent.width
                                height:             parent.height * (_focusLevel / 100)
                                radius:             width * 0.5
                                color:              qgcPal.colorBlue
                            }
                        }

                        MouseArea {
                            anchors.fill:   parent
                            onPressed:      (mouse) => { _updateFocus(mouse.y) }
                            onPositionChanged: (mouse) => { _updateFocus(mouse.y) }

                            function _updateFocus(my) {
                                var level = Math.max(0, Math.min(100, (1 - my / parent.height) * 100))
                                if (_hasRealCamera) {
                                    _camera.setFocusLevel(level)
                                } else {
                                    _mockFocusLevel = level
                                }
                            }
                        }
                    }

                    // Focus level label
                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               Math.round(_focusLevel) + "%"
                        font.pointSize:     ScreenTools.smallFontPointSize
                        color:              qgcPal.text
                    }
                }

                // Separator
                Rectangle {
                    width: parent.width; height: 1
                    color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3)
                    visible: !_hasRealCamera || (_camera && _camera.hasFocus)
                }

                // ═══════════════════════════════════════
                // LENS SELECTION SECTION
                // ═══════════════════════════════════════
                Column {
                    width:      parent.width
                    spacing:    _sectionSpacing

                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               qsTr("LENS")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                        color:              qgcPal.text
                    }

                    // W / Z / T toggle buttons
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing:    2

                        Repeater {
                            model: [
                                { label: "W", mode: 0 },
                                { label: "Z", mode: 1 },
                                { label: "T", mode: 2 }
                            ]

                            Rectangle {
                                width:      (_panelWidth - (_margins * 2) - 4) / 3
                                height:     _smallButtonSize * 0.65
                                radius:     ScreenTools.defaultFontPixelWidth * 0.3
                                color:      _lensMode === modelData.mode ? qgcPal.colorGreen : qgcPal.button
                                border.width: 1
                                border.color: qgcPal.buttonText

                                QGCLabel {
                                    anchors.centerIn:   parent
                                    text:               modelData.label
                                    font.pointSize:     ScreenTools.smallFontPointSize
                                    font.bold:          true
                                    color:              _lensMode === modelData.mode ? "white" : qgcPal.buttonText
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (_hasRealCamera && _activeVehicle) {
                                            // MAV_CMD_SET_CAMERA_SOURCE (534), param2=lensId
                                            _activeVehicle.sendCommand(_camera.compID, 534, false, 0, modelData.mode)
                                        }
                                        _mockLensMode = modelData.mode
                                    }
                                }
                            }
                        }
                    }
                }

                // Separator
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3) }

                // ═══════════════════════════════════════
                // GIMBAL SECTION
                // ═══════════════════════════════════════
                Column {
                    width:      parent.width
                    spacing:    _sectionSpacing

                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:               qsTr("GIMBAL")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                        color:              qgcPal.text
                    }

                    // Gimbal control pad
                    Item {
                        id:     gimbalPad
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:  _gimbalPadSize
                        height: width

                        property real _padCenterX: width / 2
                        property real _padCenterY: height / 2
                        property real _padRadius:  width / 2
                        property real _stickX:     0
                        property real _stickY:     0

                        Rectangle {
                            anchors.fill:   parent
                            radius:         width * 0.5
                            color:          "transparent"
                            border.width:   1
                            border.color:   Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.4)
                        }

                        Rectangle {
                            anchors.centerIn:   parent
                            width:              parent.width * 0.7
                            height:             1
                            color:              Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.2)
                        }
                        Rectangle {
                            anchors.centerIn:   parent
                            width:              1
                            height:             parent.height * 0.7
                            color:              Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.2)
                        }

                        // Direction arrows
                        QGCLabel {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top:            parent.top
                            anchors.topMargin:      2
                            text:                   "\u25B2"
                            font.pointSize:         ScreenTools.smallFontPointSize * _scaleFactor
                            color:                  Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.6)
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -_margins
                                onClicked: _root._gimbalStep(0, 0.2)
                            }
                        }
                        QGCLabel {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom:         parent.bottom
                            anchors.bottomMargin:   2
                            text:                   "\u25BC"
                            font.pointSize:         ScreenTools.smallFontPointSize * _scaleFactor
                            color:                  Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.6)
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -_margins
                                onClicked: _root._gimbalStep(0, -0.2)
                            }
                        }
                        QGCLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:           parent.left
                            anchors.leftMargin:     2
                            text:                   "\u25C0"
                            font.pointSize:         ScreenTools.smallFontPointSize * _scaleFactor
                            color:                  Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.6)
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -_margins
                                onClicked: _root._gimbalStep(-0.2, 0)
                            }
                        }
                        QGCLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right:          parent.right
                            anchors.rightMargin:    2
                            text:                   "\u25B6"
                            font.pointSize:         ScreenTools.smallFontPointSize * _scaleFactor
                            color:                  Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.6)
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -_margins
                                onClicked: _root._gimbalStep(0.2, 0)
                            }
                        }

                        // Stick indicator
                        Rectangle {
                            width:  ScreenTools.defaultFontPixelWidth
                            height: width
                            radius: width * 0.5
                            color:  qgcPal.colorGreen
                            x:      gimbalPad._padCenterX + (gimbalPad._stickX * gimbalPad._padRadius * 0.6) - (width / 2)
                            y:      gimbalPad._padCenterY - (gimbalPad._stickY * gimbalPad._padRadius * 0.6) - (height / 2)
                        }

                        // Touch/Drag area
                        MouseArea {
                            anchors.fill: parent
                            onPressed: (mouse) => { _updateGimbalFromMouse(mouse.x, mouse.y) }
                            onPositionChanged: (mouse) => { _updateGimbalFromMouse(mouse.x, mouse.y) }
                            onReleased: { }

                            function _updateGimbalFromMouse(mx, my) {
                                var dx = (mx - gimbalPad._padCenterX) / gimbalPad._padRadius
                                var dy = -(my - gimbalPad._padCenterY) / gimbalPad._padRadius
                                var dist = Math.sqrt(dx * dx + dy * dy)
                                if (dist > 1) { dx /= dist; dy /= dist }
                                gimbalPad._stickX = dx
                                gimbalPad._stickY = dy
                                _root._applyGimbal(dx, dy)
                            }
                        }
                    }

                    // Gimbal angle display
                    QGCLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            var pitch = _hasGimbal ? _activeGimbal.absolutePitch : _mockGimbalPitch
                            var yaw   = _hasGimbal ? _activeGimbal.absoluteYaw : _mockGimbalYaw
                            return "P:" + Math.round(pitch) + " Y:" + Math.round(yaw)
                        }
                        font.pointSize:     ScreenTools.smallFontPointSize
                        color:              qgcPal.text
                    }

                    // HOME (reset) button
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:                  _smallButtonSize * 1.3
                        height:                 _smallButtonSize * 0.65
                        radius:                 ScreenTools.defaultFontPixelWidth * 0.3
                        color:                  homeMA.pressed ? qgcPal.buttonHighlight : qgcPal.button
                        border.width:           1
                        border.color:           qgcPal.buttonText

                        QGCLabel {
                            anchors.centerIn:   parent
                            text:               qsTr("RST")
                            font.pointSize:     ScreenTools.smallFontPointSize
                            font.bold:          true
                            color:              qgcPal.buttonText
                        }

                        MouseArea {
                            id:             homeMA
                            anchors.fill:   parent
                            onClicked: {
                                gimbalPad._stickX = 0
                                gimbalPad._stickY = 0
                                _mockGimbalPitch = 0
                                _mockGimbalYaw = 0
                                if (_hasGimbal) {
                                    _gimbalController.gimbalOnScreenControl(0, 0, true, false, false)
                                } else if (_activeVehicle) {
                                    // Direct MAVLink: reset gimbal to 0,0
                                    // flags: ROLL_LOCK(4) | PITCH_LOCK(8) | YAW_IN_VEHICLE_FRAME(32) = 44
                                    _activeVehicle.sendCommand(1, 287, false, 0, 0, NaN, NaN, 44, 0, 0)
                                }
                            }
                        }
                    }
                }

                // Separator
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3) }

                // Tracking toggle
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:              _smallButtonSize * 1.3
                    height:             _smallButtonSize * 0.65
                    radius:             ScreenTools.defaultFontPixelWidth * 0.3
                    color:              _trackingEnabled ? qgcPal.colorGreen : (trkMA.pressed ? qgcPal.buttonHighlight : qgcPal.button)
                    border.width:       1
                    border.color:       qgcPal.buttonText

                    QGCLabel {
                        anchors.centerIn:   parent
                        text:               qsTr("TRK")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                        color:              _trackingEnabled ? "white" : qgcPal.buttonText
                    }

                    MouseArea {
                        id:             trkMA
                        anchors.fill:   parent
                        onClicked: {
                            if (_hasRealCamera) {
                                _camera.trackingEnabled = !_camera.trackingEnabled
                            } else {
                                _mockTrackingEnabled = !_mockTrackingEnabled
                            }
                        }
                    }
                }

                // B&W filter toggle
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:              _smallButtonSize * 1.3
                    height:             _smallButtonSize * 0.65
                    radius:             ScreenTools.defaultFontPixelWidth * 0.3
                    color:              bwFilterEnabled ? qgcPal.colorGreen : (bwMA.pressed ? qgcPal.buttonHighlight : qgcPal.button)
                    border.width:       1
                    border.color:       qgcPal.buttonText

                    QGCLabel {
                        anchors.centerIn:   parent
                        text:               qsTr("B/W")
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                        color:              bwFilterEnabled ? "white" : qgcPal.buttonText
                    }

                    MouseArea {
                        id:             bwMA
                        anchors.fill:   parent
                        onClicked:      bwFilterEnabled = !bwFilterEnabled
                    }
                }

                // Separator
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3) }

                // Settings gear
                QGCColoredImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source:             "/res/gear-black.svg"
                    mipmap:             true
                    width:              ScreenTools.defaultFontPixelHeight * 1.2 * _scaleFactor
                    height:             width
                    sourceSize.height:  height
                    color:              qgcPal.text
                    fillMode:           Image.PreserveAspectFit

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -_margins
                        onClicked:  _rtspPopupVisible = !_rtspPopupVisible
                    }
                }

            }
        }
    }

    // Photo flash overlay
    Rectangle {
        id:             photoFlash
        anchors.fill:   parent
        color:          "white"
        opacity:        0
        visible:        opacity > 0
        z:              100
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // ═══════════════════════════════════════
    // RTSP SETTINGS MODAL (full-screen overlay via Window.contentItem)
    // ═══════════════════════════════════════
    Rectangle {
        id:             rtspModal
        parent:         _root.Window.window ? _root.Window.window.contentItem : _root
        anchors.fill:   parent
        color:          Qt.rgba(0, 0, 0, 0.6)
        visible:        _rtspPopupVisible
        z:              200

        MouseArea {
            anchors.fill: parent
            onClicked:    _rtspPopupVisible = false
        }

        Rectangle {
            id:                     rtspDialog
            anchors.centerIn:       parent
            width:                  Math.min(parent.width * 0.7, ScreenTools.defaultFontPixelWidth * 35)
            height:                 rtspDialogCol.height + (_margins * 4)
            radius:                 ScreenTools.defaultFontPixelWidth
            color:                  qgcPal.window
            border.width:           1
            border.color:           Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.3)

            MouseArea { anchors.fill: parent }

            Column {
                id:             rtspDialogCol
                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: _margins * 2
                spacing:        ScreenTools.defaultFontPixelHeight * 0.5

                // Title
                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:               qsTr("RTSP Video Stream")
                    font.pointSize:     ScreenTools.defaultFontPointSize
                    font.bold:          true
                    color:              qgcPal.text
                }

                // Current source
                QGCLabel {
                    width:              parent.width
                    text:               qsTr("Source: ") + _videoSettings.videoSource.rawValue
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.text
                    elide:              Text.ElideRight
                }

                // Spacer
                Item { width: 1; height: _margins }

                // URL label
                QGCLabel {
                    text:               qsTr("RTSP URL")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    font.bold:          true
                    color:              qgcPal.text
                }

                // URL input field
                Rectangle {
                    width:          parent.width
                    height:         rtspInput.contentHeight + ScreenTools.defaultFontPixelHeight * 0.8
                    radius:         ScreenTools.defaultFontPixelWidth * 0.3
                    color:          qgcPal.windowShade
                    border.width:   1
                    border.color:   rtspInput.activeFocus ? qgcPal.colorGreen : qgcPal.buttonText

                    TextInput {
                        id:                 rtspInput
                        anchors.left:       parent.left
                        anchors.right:      parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins:    _margins
                        text:               _videoSettings.rtspUrl.rawValue || "rtsp://192.168.2.119:554"
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.family:        ScreenTools.fixedFontFamily
                        color:              qgcPal.text
                        selectByMouse:      true
                        clip:               true
                    }
                }

                // Spacer
                Item { width: 1; height: _margins }

                // Buttons row
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing:    ScreenTools.defaultFontPixelWidth

                    // Cancel button
                    Rectangle {
                        width:          ScreenTools.defaultFontPixelWidth * 8
                        height:         ScreenTools.defaultFontPixelHeight * 2
                        radius:         ScreenTools.defaultFontPixelWidth * 0.3
                        color:          cancelMA.pressed ? qgcPal.buttonHighlight : qgcPal.button
                        border.width:   1
                        border.color:   qgcPal.buttonText

                        QGCLabel {
                            anchors.centerIn: parent
                            text:           qsTr("Cancel")
                            color:          qgcPal.buttonText
                        }

                        MouseArea {
                            id:             cancelMA
                            anchors.fill:   parent
                            onClicked:      _rtspPopupVisible = false
                        }
                    }

                    // Apply button
                    Rectangle {
                        width:          ScreenTools.defaultFontPixelWidth * 8
                        height:         ScreenTools.defaultFontPixelHeight * 2
                        radius:         ScreenTools.defaultFontPixelWidth * 0.3
                        color:          applyMA.pressed ? qgcPal.buttonHighlight : qgcPal.colorGreen
                        border.width:   1
                        border.color:   qgcPal.buttonText

                        QGCLabel {
                            anchors.centerIn: parent
                            text:           qsTr("Apply")
                            font.bold:      true
                            color:          "white"
                        }

                        MouseArea {
                            id:             applyMA
                            anchors.fill:   parent
                            onClicked: {
                                _videoSettings.videoSource.rawValue = _videoSettings.rtspVideoSource
                                _videoSettings.rtspUrl.rawValue = rtspInput.text
                                _rtspPopupVisible = false
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════

    // Zoom step: sends MAV_CMD_SET_CAMERA_ZOOM (531) directly to bypass hasZoom capability check
    // param1: 1 = ZOOM_TYPE_STEP, param2: direction (-1 wide, +1 tele)
    function _zoomStep(direction) {
        if (_activeVehicle) {
            if (_hasRealCamera && _camera.hasZoom) {
                _camera.stepZoom(direction)
            } else {
                // Direct MAVLink fallback — works even if camera doesn't report zoom capability
                var compId = _hasRealCamera ? _camera.compID : 1
                _activeVehicle.sendCommand(compId, 531, false, 1, direction)
            }
        }
        // Always update mock for visual feedback
        if (direction > 0) {
            _mockZoomLevel = Math.min(100, _mockZoomLevel + 10)
        } else {
            _mockZoomLevel = Math.max(0, _mockZoomLevel - 10)
        }
    }

    // Gimbal step (discrete): sends MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW (287) directly
    // as fallback when gimbal not detected via gimbal manager protocol
    function _gimbalStep(dx, dy) {
        if (_hasGimbal) {
            _gimbalController.gimbalOnScreenControl(dx, dy, true, false, false)
        } else if (_activeVehicle) {
            // Direct MAVLink fallback: send pitch/yaw angle increment
            // MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW: param1=pitch, param2=yaw, param5=flags, param7=deviceId
            var pitchInc = dy * 15   // degrees per step
            var yawInc   = dx * 15
            var currentPitch = _mockGimbalPitch
            var currentYaw   = _mockGimbalYaw
            var newPitch = Math.max(-90, Math.min(45, currentPitch + pitchInc))
            var newYaw   = Math.max(-180, Math.min(180, currentYaw + yawInc))
            // flags: ROLL_LOCK(4) | PITCH_LOCK(8) | YAW_IN_VEHICLE_FRAME(32) = 44
            _activeVehicle.sendCommand(1, 287, false, newPitch, newYaw, NaN, NaN, 44, 0, 0)
            _mockGimbalPitch = newPitch
            _mockGimbalYaw   = newYaw
        } else {
            _mockGimbalYaw   = Math.max(-180, Math.min(180, _mockGimbalYaw   + dx * 45))
            _mockGimbalPitch = Math.max(-90,  Math.min(90,  _mockGimbalPitch + dy * 45))
        }
    }

    // Gimbal drag (continuous): sends gimbal commands from pad drag
    function _applyGimbal(dx, dy) {
        if (_hasGimbal) {
            _gimbalController.gimbalOnScreenControl(dx, dy, false, true, true)
        } else if (_activeVehicle) {
            // Direct MAVLink: map pad position to absolute angle
            var pitch = dy * 45    // ±45 deg range
            var yaw   = dx * 90    // ±90 deg range
            // flags: ROLL_LOCK(4) | PITCH_LOCK(8) | YAW_IN_VEHICLE_FRAME(32) = 44
            _activeVehicle.sendCommand(1, 287, false, pitch, yaw, NaN, NaN, 44, 0, 0)
            _mockGimbalPitch = pitch
            _mockGimbalYaw   = yaw
        } else {
            _mockGimbalYaw   = Math.max(-180, Math.min(180, dx * 180))
            _mockGimbalPitch = Math.max(-90,  Math.min(90,  dy * 90))
        }
    }

    function _triggerCapture() {
        if (_isPhotoMode) {
            if (_hasRealCamera) {
                _camera.takePhoto()
            } else if (_activeVehicle) {
                // MAV_CMD_IMAGE_START_CAPTURE (2000): param3=1 (single capture)
                _activeVehicle.sendCommand(1, 2000, false, 0, 0, 1)
            }
            _mockPhotoCount++
            photoFlash.opacity = 0.6
            mockPhotoFlashTimer.start()
        } else {
            if (_hasRealCamera) {
                _camera.toggleVideoRecording()
            } else {
                if (_mockRecording) {
                    _mockRecording = false
                    _mockRecordSeconds = 0
                    if (_activeVehicle) {
                        // MAV_CMD_VIDEO_STOP_CAPTURE (2501)
                        _activeVehicle.sendCommand(1, 2501, false)
                    }
                } else {
                    _mockRecording = true
                    _mockRecordSeconds = 0
                    if (_activeVehicle) {
                        // MAV_CMD_VIDEO_START_CAPTURE (2500)
                        _activeVehicle.sendCommand(1, 2500, false, 0, 0)
                    }
                }
            }
        }
    }

    function _formatTime(totalSeconds) {
        var hours   = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        return _pad(hours) + ":" + _pad(minutes) + ":" + _pad(seconds)
    }

    function _pad(n) {
        return n < 10 ? "0" + n : "" + n
    }
}
