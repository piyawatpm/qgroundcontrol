#include "ViewLinkController.h"

#include <QtCore/QApplicationStatic>
#include <QtNetwork/QTcpSocket>

#include "QGCLoggingCategory.h"

QGC_LOGGING_CATEGORY(ViewLinkLog, "ViewLink.Controller")

Q_APPLICATION_STATIC(ViewLinkController, _viewLinkInstance);

ViewLinkController::ViewLinkController(QObject *parent)
    : QObject(parent)
{
    qCWarning(ViewLinkLog) << "ViewLinkController created (FF protocol)";

    _socket = new QTcpSocket(this);
    connect(_socket, &QTcpSocket::connected,    this, &ViewLinkController::_onConnected);
    connect(_socket, &QTcpSocket::disconnected, this, &ViewLinkController::_onDisconnected);
    connect(_socket, &QTcpSocket::readyRead,    this, &ViewLinkController::_onReadyRead);
    connect(_socket, &QTcpSocket::errorOccurred, this, &ViewLinkController::_onSocketError);

    // Reconnect timer: try reconnect every 3s on disconnect
    _reconnectTimer.setInterval(3000);
    connect(&_reconnectTimer, &QTimer::timeout, this, [this]() {
        if (!_connected && !_host.isEmpty()) {
            qCWarning(ViewLinkLog) << "Attempting reconnect to" << _host << _port;
            _socket->connectToHost(_host, _port);
        }
    });
}

ViewLinkController::~ViewLinkController()
{
    qCWarning(ViewLinkLog) << "ViewLinkController destroyed";
}

ViewLinkController *ViewLinkController::instance()
{
    return _viewLinkInstance();
}

// ═══════════════════════════════════════════════════════════════════
//  CONNECTION
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::connectToCamera(const QString &host, int port)
{
    _host = host;
    _port = port;

    qCWarning(ViewLinkLog) << "Connecting to" << host << port;
    _reconnectTimer.stop();
    _socket->abort();
    _socket->connectToHost(host, port);
}

void ViewLinkController::disconnectCamera()
{
    qCWarning(ViewLinkLog) << "Disconnecting";
    _reconnectTimer.stop();
    _host.clear();
    _socket->abort();
}

void ViewLinkController::_onConnected()
{
    qCWarning(ViewLinkLog) << "=== Connected to camera at" << _host << _port << "(FF protocol) ===";
    _connected = true;
    _reconnectTimer.stop();
    emit connectedChanged();
}

void ViewLinkController::_onDisconnected()
{
    qCWarning(ViewLinkLog) << "Disconnected from camera";
    _connected = false;
    emit connectedChanged();

    if (!_host.isEmpty()) {
        _reconnectTimer.start();
    }
}

void ViewLinkController::_onSocketError(QAbstractSocket::SocketError error)
{
    qCWarning(ViewLinkLog) << "Socket error:" << error << _socket->errorString();
    if (!_connected && !_host.isEmpty()) {
        _reconnectTimer.start();
    }
}

void ViewLinkController::_onReadyRead()
{
    QByteArray data = _socket->readAll();
    static int rxLogCount = 0;
    if (rxLogCount < 10 || (rxLogCount % 200) == 0) {
        qCWarning(ViewLinkLog) << "RX[" << rxLogCount << "]" << data.size() << "bytes:" << data.toHex(' ');
    }
    rxLogCount++;
    _rxBuffer.append(data);
    _tryParseBuffer();
}

// ═══════════════════════════════════════════════════════════════════
//  FF COMMAND PROTOCOL
//
//  Discovered by reverse-engineering PodControl::sendUpCMD from
//  QGroundcontrol_ZT_A_101.apk (Chinese Viewpro QGC).
//
//  Command (host → camera):  FF <b1> <b2> <b3> <b4> <b5> <SUM>
//    - 7 bytes total, sent directly to TCP socket
//    - SUM = (b1 + b2 + b3 + b4 + b5) & 0xFF
//
//  Response (camera → host): EE 01 1D <26 data bytes> <SUM>
//    - 29 bytes total, camera auto-broadcasts continuously
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::_sendCmd(uint8_t b1, uint8_t b2, uint8_t b3, uint8_t b4, uint8_t b5)
{
    if (!_socket || _socket->state() != QAbstractSocket::ConnectedState) {
        qCWarning(ViewLinkLog) << "TX FAILED - not connected";
        return;
    }

    QByteArray pkt;
    pkt.append(static_cast<char>(0xFF));
    pkt.append(static_cast<char>(b1));
    pkt.append(static_cast<char>(b2));
    pkt.append(static_cast<char>(b3));
    pkt.append(static_cast<char>(b4));
    pkt.append(static_cast<char>(b5));
    uint8_t sum = static_cast<uint8_t>((b1 + b2 + b3 + b4 + b5) & 0xFF);
    pkt.append(static_cast<char>(sum));

    qCWarning(ViewLinkLog) << "TX" << pkt.toHex(' ');
    _socket->write(pkt);
}

// ═══════════════════════════════════════════════════════════════════
//  CAMERA — photo / record
//
//  b2=0x12 group:
//    b3=0x00 takePhoto
//    b3=0x01 record start
//    b3=0x02 record stop
//    b3=0x03 photo mode
//    b3=0x04 video mode
//    b3=0x05 video resolution (b4: 0=4K, 1=2K, 2=1080P, 3=720P)
//    b3=0x06 photo resolution (b4: 0=24M, 1=20M, 2=16M, 3=7M)
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::takePhoto()
{
    qCWarning(ViewLinkLog) << "takePhoto";
    _sendCmd(0x01, 0x12, 0x00, 0x00, 0x00);
}

void ViewLinkController::startRecord()
{
    qCWarning(ViewLinkLog) << "startRecord";
    _sendCmd(0x01, 0x12, 0x01, 0x00, 0x00);
}

void ViewLinkController::stopRecord()
{
    qCWarning(ViewLinkLog) << "stopRecord";
    _sendCmd(0x01, 0x12, 0x02, 0x00, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  ZOOM — b3 bitmask in gimbal group
//
//  b3=0x40 zoom in,  b4=speed (1-255)
//  b3=0x20 zoom out, b4=speed (1-255)
//  b3=0x60 zoom stop
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::zoomIn(int speed)
{
    speed = qBound(1, speed, 255);
    qCWarning(ViewLinkLog) << "zoomIn speed:" << speed;
    _sendCmd(0x01, 0x00, 0x40, static_cast<uint8_t>(speed), 0x00);
}

void ViewLinkController::zoomOut(int speed)
{
    speed = qBound(1, speed, 255);
    qCWarning(ViewLinkLog) << "zoomOut speed:" << speed;
    _sendCmd(0x01, 0x00, 0x20, static_cast<uint8_t>(speed), 0x00);
}

void ViewLinkController::zoomStop()
{
    qCWarning(ViewLinkLog) << "zoomStop";
    _sendCmd(0x01, 0x00, 0x60, 0x00, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  ZOOM SET — electronic magnification
//  b2=0x17: b4=magnification value
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::setZoomEO(int magnification10x)
{
    qCWarning(ViewLinkLog) << "setZoomEO:" << magnification10x;
    uint8_t val = static_cast<uint8_t>(qBound(1, magnification10x / 10, 255));
    _sendCmd(0x01, 0x17, 0x00, val, 0x00);
}

void ViewLinkController::setZoomIR(int magnification10x)
{
    qCWarning(ViewLinkLog) << "setZoomIR:" << magnification10x;
    setZoomEO(magnification10x);
}

// ═══════════════════════════════════════════════════════════════════
//  FOCUS
//  b2=0x1D: b3=0x00 manual focus open, b3=0x01 manual focus close
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::autoFocus()
{
    qCWarning(ViewLinkLog) << "autoFocus (disable manual focus)";
    _sendCmd(0x01, 0x1D, 0x01, 0x00, 0x00);
}

void ViewLinkController::manualFocusIn()
{
    qCWarning(ViewLinkLog) << "manualFocusIn";
    _sendCmd(0x01, 0x1D, 0x00, 0x00, 0x00);
}

void ViewLinkController::manualFocusOut()
{
    qCWarning(ViewLinkLog) << "manualFocusOut";
    _sendCmd(0x01, 0x1D, 0x01, 0x00, 0x00);
}

void ViewLinkController::focusStop()
{
    qCWarning(ViewLinkLog) << "focusStop";
    _sendCmd(0x01, 0x1D, 0x01, 0x00, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  VIDEO SOURCE
//  b2=0x14: b4=source
//    0 = vis+thermal (PIP EO primary)
//    1 = thermal+vis (PIP IR primary)
//    2 = visible light only (EO)
//    3 = thermal imaging only (IR)
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::setVideoSource(int source)
{
    qCWarning(ViewLinkLog) << "setVideoSource:" << source;
    uint8_t src = static_cast<uint8_t>(qBound(0, source, 3));
    _sendCmd(0x01, 0x14, 0x00, src, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  COLOR PALETTE (thermal)
//  b2=0x15: b4=palette
//    0 = white heat
//    1 = black heat
//    2 = rainbow
//    3 = lava
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::setColorPalette(int mode)
{
    qCWarning(ViewLinkLog) << "setColorPalette:" << mode;
    uint8_t m = static_cast<uint8_t>(qBound(0, mode, 3));
    _sendCmd(0x01, 0x15, 0x00, m, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  LASER RANGING
//  b2=0x16: b3=0x01 open, b3=0x02 close
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::laserRangeOnce()
{
    qCWarning(ViewLinkLog) << "laserRangeOnce";
    _sendCmd(0x01, 0x16, 0x01, 0x00, 0x00);
}

void ViewLinkController::laserRangeContinuous()
{
    qCWarning(ViewLinkLog) << "laserRangeContinuous";
    _sendCmd(0x01, 0x16, 0x01, 0x00, 0x00);
}

void ViewLinkController::laserRangeStop()
{
    qCWarning(ViewLinkLog) << "laserRangeStop";
    _sendCmd(0x01, 0x16, 0x02, 0x00, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  GIMBAL SPEED — direction bitmask + speed bytes
//
//  b3 direction bitmask:
//    0x02 = right    0x04 = left
//    0x08 = up       0x10 = down
//    Combinations: 0x0A=right+up, 0x0C=left+up, 0x12=right+down, 0x14=left+down
//  b4 = yaw/pan speed   (0-255)
//  b5 = pitch/tilt speed (0-255)
//  b3=0x00, b4=0x00, b5=0x00 = STOP
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::gimbalSpeed(float yawDegS, float pitchDegS)
{
    static constexpr float MAX_SPEED = 30.0f;

    uint8_t dirBits = 0;
    uint8_t yawSpeed = 0;
    uint8_t pitchSpeed = 0;

    if (yawDegS > 0.5f) {
        dirBits |= 0x02; // right
        yawSpeed = static_cast<uint8_t>(qBound(1, static_cast<int>(qAbs(yawDegS) * 255.0f / MAX_SPEED), 255));
    } else if (yawDegS < -0.5f) {
        dirBits |= 0x04; // left
        yawSpeed = static_cast<uint8_t>(qBound(1, static_cast<int>(qAbs(yawDegS) * 255.0f / MAX_SPEED), 255));
    }

    if (pitchDegS > 0.5f) {
        dirBits |= 0x08; // up
        pitchSpeed = static_cast<uint8_t>(qBound(1, static_cast<int>(qAbs(pitchDegS) * 255.0f / MAX_SPEED), 255));
    } else if (pitchDegS < -0.5f) {
        dirBits |= 0x10; // down
        pitchSpeed = static_cast<uint8_t>(qBound(1, static_cast<int>(qAbs(pitchDegS) * 255.0f / MAX_SPEED), 255));
    }

    if (dirBits == 0) {
        _sendCmd(0x01, 0x00, 0x00, 0x00, 0x00); // stop
    } else {
        _sendCmd(0x01, 0x00, dirBits, yawSpeed, pitchSpeed);
    }
}

void ViewLinkController::gimbalAngle(float yawDeg, float pitchDeg)
{
    // FF protocol only supports speed-based gimbal control
    qCWarning(ViewLinkLog) << "gimbalAngle not supported in FF protocol";
    Q_UNUSED(yawDeg);
    Q_UNUSED(pitchDeg);
}

// ═══════════════════════════════════════════════════════════════════
//  GIMBAL MODES
//  b2=0x13: b3=mode
//    0x00 = follow
//    0x01 = lock
//    0x02 = auto down (look straight down)
//    0x03 = auto center (home)
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::gimbalHome()
{
    qCWarning(ViewLinkLog) << "gimbalHome (center)";
    _sendCmd(0x01, 0x13, 0x03, 0x00, 0x00);
}

void ViewLinkController::gimbalLock()
{
    qCWarning(ViewLinkLog) << "gimbalLock";
    _sendCmd(0x01, 0x13, 0x01, 0x00, 0x00);
}

void ViewLinkController::gimbalFollow()
{
    qCWarning(ViewLinkLog) << "gimbalFollow";
    _sendCmd(0x01, 0x13, 0x00, 0x00, 0x00);
}

void ViewLinkController::gimbalDown()
{
    qCWarning(ViewLinkLog) << "gimbalDown";
    _sendCmd(0x01, 0x13, 0x02, 0x00, 0x00);
}

// ═══════════════════════════════════════════════════════════════════
//  TRACKING
//  b2=0x11:
//    b3=0x00 point tracking on, b4=xNorm(0-255), b5=yNorm(0-255)
//    b3=0x01 tracking off
//    b3=0x02 target detection on
//    b3=0x03 target detection off
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::trackPoint(float screenX, float screenY)
{
    qCWarning(ViewLinkLog) << "trackPoint x:" << screenX << "y:" << screenY;
    // Normalize 0.0-1.0 → 0-255 byte range (matching Chinese APK)
    uint8_t xN = static_cast<uint8_t>(qBound(0, static_cast<int>(screenX * 255.0f), 255));
    uint8_t yN = static_cast<uint8_t>(qBound(0, static_cast<int>(screenY * 255.0f), 255));
    _sendCmd(0x01, 0x11, 0x00, xN, yN);
}

void ViewLinkController::trackStop()
{
    qCWarning(ViewLinkLog) << "trackStop";
    _sendCmd(0x01, 0x11, 0x01, 0x00, 0x00);
}

void ViewLinkController::trackOpen()
{
    // No separate "open" in FF protocol — trackPoint starts tracking directly
    qCWarning(ViewLinkLog) << "trackOpen (no-op, use trackPoint)";
}

void ViewLinkController::setTrackBoxSize(int size)
{
    Q_UNUSED(size);
    qCWarning(ViewLinkLog) << "setTrackBoxSize not available in FF protocol";
}

// ═══════════════════════════════════════════════════════════════════
//  STATE QUERY
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::queryGimbalState()
{
    // Camera auto-broadcasts EE status — no explicit query needed
}

// ═══════════════════════════════════════════════════════════════════
//  EE RESPONSE PARSING
//
//  Format (29 bytes, camera auto-broadcasts):
//    [0]     0xEE header
//    [1]     0x01 type
//    [2]     0x1D length (29)
//    [3-4]   laserRange  (uint16 BE, raw)
//    [5-6]   podRoll     (int16 BE, raw — scaling TBD)
//    [7-8]   podPitch    (int16 BE, raw — scaling TBD)
//    [9-10]  podYaw      (int16 BE, raw — scaling TBD)
//    [11]    zoomRatio   (uint8)
//    [12]    trackState  (uint8)
//    [13-16] longitude   (uint32 BE)
//    [17-20] latitude    (uint32 BE)
//    [21-22] height      (uint16 BE)
//    [23-26] reserved    (uint32)
//    [27]    podState    (uint8)
//    [28]    checksum    (additive sum of bytes 0-27)
// ═══════════════════════════════════════════════════════════════════

void ViewLinkController::_tryParseBuffer()
{
    while (!_rxBuffer.isEmpty()) {
        uint8_t byte = static_cast<uint8_t>(_rxBuffer[0]);
        _rxBuffer.remove(0, 1);

        switch (_parseState) {
        case IDLE:
            if (byte == EE_HEAD) {
                _parsePacket.clear();
                _parsePacket.append(static_cast<char>(byte));
                _parseState = EE_GOT_HEAD;
            }
            break;

        case EE_GOT_HEAD:
            _parsePacket.append(static_cast<char>(byte));
            _parseState = EE_GOT_TYPE;
            break;

        case EE_GOT_TYPE:
            _eeLen = byte;
            _parsePacket.append(static_cast<char>(byte));
            if (_eeLen < 4 || _eeLen > 200) {
                _parseState = IDLE;
            } else {
                _parseState = EE_COLLECTING;
            }
            break;

        case EE_COLLECTING:
            _parsePacket.append(static_cast<char>(byte));
            if (_parsePacket.size() >= _eeLen) {
                // Verify additive checksum
                uint8_t sum = 0;
                for (int i = 0; i < _parsePacket.size() - 1; i++) {
                    sum += static_cast<uint8_t>(_parsePacket[i]);
                }
                uint8_t rxSum = static_cast<uint8_t>(_parsePacket[_parsePacket.size() - 1]);
                if (sum == rxSum) {
                    _parseEEResponse(_parsePacket);
                } else {
                    qCWarning(ViewLinkLog) << "EE checksum mismatch: calc=" << sum << "rx=" << rxSum;
                }
                _parseState = IDLE;
            }
            break;

        default:
            _parseState = IDLE;
            break;
        }
    }
}

void ViewLinkController::_parseEEResponse(const QByteArray &packet)
{
    if (packet.size() < 29) {
        static int shortCount = 0;
        if (shortCount < 10) {
            qCWarning(ViewLinkLog) << "EE packet short:" << packet.size() << "bytes";
        }
        shortCount++;
        return;
    }

    const uint8_t *d = reinterpret_cast<const uint8_t*>(packet.constData());
    bool changed = false;

    // Laser range: bytes [3-4] uint16 big-endian, divided by 10 for meters
    uint16_t rangeRaw = static_cast<uint16_t>((d[3] << 8) | d[4]);
    float newRange = rangeRaw / 10.0f;
    if (_laserRange != newRange) { _laserRange = newRange; changed = true; }

    // Roll: bytes [5-6] int16 big-endian
    auto rollRaw = static_cast<int16_t>((d[5] << 8) | d[6]);
    float newRoll = rollRaw / 10.0f;
    if (_gimbalRoll != newRoll) { _gimbalRoll = newRoll; changed = true; }

    // Pitch: bytes [7-8] int16 big-endian
    auto pitchRaw = static_cast<int16_t>((d[7] << 8) | d[8]);
    float newPitch = pitchRaw / 10.0f;
    if (_gimbalPitch != newPitch) { _gimbalPitch = newPitch; changed = true; }

    // Yaw: bytes [9-10] int16 big-endian
    auto yawRaw = static_cast<int16_t>((d[9] << 8) | d[10]);
    float newYaw = yawRaw / 10.0f;
    if (_gimbalYaw != newYaw) { _gimbalYaw = newYaw; changed = true; }

    // Zoom ratio: byte [11]
    float newEoZoom = static_cast<float>(d[11]);
    if (_eoZoom != newEoZoom) { _eoZoom = newEoZoom; changed = true; }

    // Tracking state: byte [12]
    int newTrackState = d[12];
    if (_trackState != newTrackState) { _trackState = newTrackState; changed = true; }

    // Pod state: byte [27] — may contain recording/video source bits
    uint8_t podState = d[27];
    Q_UNUSED(podState);

    if (changed) {
        static int stateLogCount = 0;
        if (stateLogCount < 30 || (stateLogCount % 100) == 0) {
            qCWarning(ViewLinkLog) << "State[" << stateLogCount << "]:"
                                   << "pitch=" << _gimbalPitch
                                   << "yaw=" << _gimbalYaw
                                   << "roll=" << _gimbalRoll
                                   << "zoom=" << _eoZoom
                                   << "track=" << _trackState
                                   << "range=" << _laserRange
                                   << "podState=0x" << Qt::hex << podState;
        }
        stateLogCount++;
        emit gimbalStateChanged();
    }
}
