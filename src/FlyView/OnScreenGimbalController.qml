import QtQuick

import QGroundControl
import QGroundControl.Controls

Item {
    id:             rootItem
    anchors.fill:   parent

    property var screenX
    property var screenY
    property var screenXrateInitCoocked
    property var screenYrateInitCoocked

    property var  activeVehicle:                QGroundControl.multiVehicleManager.activeVehicle
    property var  gimbalController:             activeVehicle ? activeVehicle.gimbalController : undefined
    property var  activeGimbal:                 gimbalController ? gimbalController.activeGimbal : undefined
    property bool gimbalAvailable:              activeGimbal != undefined
    property var  gimbalControllerSettings:     QGroundControl.settingsManager.gimbalControllerSettings
    property bool cameraTrackingEnabled:        false // Used to ignore clicks when camera tracking operation is active, otherwise it would collide with these gimbal controls
    // Allow control when gimbal is detected OR when vehicle is connected (fallback to direct MAVLink)
    property bool shouldProcessClicks:          gimbalControllerSettings.EnableOnScreenControl.value && (activeGimbal || activeVehicle) && !cameraTrackingEnabled ? true : false

    function clickControl() {
        if (!shouldProcessClicks) {
            return
        }
        // If click and slide control, return, it uses press and release
        if (!gimbalControllerSettings.ControlType.rawValue == 0) {
            return
        }
        clickAndPoint(x, y)
    }

    // Sends a +-(0-1) xy value to vehicle.gimbalController.gimbalOnScreenControl
    function clickAndPoint() {
        var xCoocked =  ( (screenX / parent.width)  * 2) - 1
        var yCoocked = -( (screenY / parent.height) * 2) + 1
        if (rootItem.gimbalAvailable) {
            gimbalController.gimbalOnScreenControl(xCoocked, yCoocked, true, false, false)
        } else if (rootItem.activeVehicle) {
            // Fallback: send MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW (287) directly
            // Map screen coordinates to pitch/yaw angles
            var hFov = gimbalControllerSettings.CameraHFov.rawValue
            var vFov = gimbalControllerSettings.CameraVFov.rawValue
            var yawInc   = xCoocked * hFov * 0.5
            var pitchInc = yCoocked * vFov * 0.5
            // flags: ROLL_LOCK(4) | PITCH_LOCK(8) | YAW_IN_VEHICLE_FRAME(32) = 44
            rootItem.activeVehicle.sendCommand(1, 287, false, pitchInc, yawInc, NaN, NaN, 44, 0, 0)
        }
    }

    function pressControl() {
        if (!shouldProcessClicks) {
            return
        }
        // If click and point control return, that is handled exclusively on clickAndPoint()
        if (!gimbalControllerSettings.ControlType.rawValue == 1) {
            return
        }
        sendRateTimer.start()
        screenXrateInitCoocked =  ( ( screenX / parent.width)  * 2) - 1
        screenYrateInitCoocked = -( ( screenY / parent.height) * 2) + 1
    }

    function releaseControl() {
        if (!shouldProcessClicks) {
            return
        }
        // If click and point control return, that is handled exclusively on clickAndPoint()
        if (!gimbalControllerSettings.ControlType.rawValue == 1) {
            return
        }
        sendRateTimer.stop()
        screenXrateInitCoocked = null
        screenYrateInitCoocked = null
    }

    Timer {
        id:             sendRateTimer
        interval:       100
        repeat:         true
        onTriggered: {
            var xCoocked =  ( ( screenX / parent.width)  * 2) - 1
            var yCoocked = -( ( screenY / parent.height) * 2) + 1
            xCoocked -= screenXrateInitCoocked
            yCoocked -= screenYrateInitCoocked
            if (rootItem.gimbalAvailable) {
                gimbalController.gimbalOnScreenControl(xCoocked, yCoocked, false, true, true)
            } else if (rootItem.activeVehicle) {
                // Fallback: send direct pitch/yaw command
                var maxSpeed = gimbalControllerSettings.CameraSlideSpeed.rawValue
                var yawInc   = xCoocked * maxSpeed * 0.1
                var pitchInc = yCoocked * maxSpeed * 0.1
                // flags: ROLL_LOCK(4) | PITCH_LOCK(8) | YAW_IN_VEHICLE_FRAME(32) = 44
                rootItem.activeVehicle.sendCommand(1, 287, false, pitchInc, yawInc, NaN, NaN, 44, 0, 0)
            }
        }
    }
}
