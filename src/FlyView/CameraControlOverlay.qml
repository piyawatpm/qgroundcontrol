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

    // Video settings
    property var  _videoSettings:   QGroundControl.settingsManager.videoSettings

    // Mock state for when no real camera is connected
    property bool _isMockPhotoMode:     true
    property real _mockZoomLevel:       0
    property bool _mockRecording:       false
    property int  _mockRecordSeconds:   0
    property int  _mockPhotoCount:      0
    // Derived state — adapts to real or mock
    property bool _isPhotoMode:     _hasRealCamera ? (_camera.cameraMode === MavlinkCameraControl.CAM_MODE_PHOTO) : _isMockPhotoMode
    property bool _isVideoMode:     !_isPhotoMode
    property real _zoomLevel:       _hasRealCamera ? _camera.zoomLevel : _mockZoomLevel
    property bool _isRecording:     _hasRealCamera ? (_camera.videoCaptureStatus === MavlinkCameraControl.VIDEO_CAPTURE_STATUS_RUNNING) : _mockRecording
    property bool _isShooting:      _hasRealCamera ? (_camera.photoCaptureStatus === MavlinkCameraControl.PHOTO_CAPTURE_IN_PROGRESS) : false

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

                // Version label
                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:               "v1.01"
                    font.pointSize:     ScreenTools.smallFontPointSize * 0.85
                    color:              Qt.rgba(qgcPal.text.r, qgcPal.text.g, qgcPal.text.b, 0.5)
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
