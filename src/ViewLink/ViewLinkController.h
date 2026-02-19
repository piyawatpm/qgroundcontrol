#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QLoggingCategory>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtNetwork/QTcpSocket>
#include <QtQmlIntegration/QtQmlIntegration>

Q_DECLARE_LOGGING_CATEGORY(ViewLinkLog)

class ViewLinkController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

    Q_PROPERTY(bool    connected     READ connected     NOTIFY connectedChanged)
    Q_PROPERTY(float   gimbalPitch   READ gimbalPitch   NOTIFY gimbalStateChanged)
    Q_PROPERTY(float   gimbalYaw     READ gimbalYaw     NOTIFY gimbalStateChanged)
    Q_PROPERTY(float   gimbalRoll    READ gimbalRoll    NOTIFY gimbalStateChanged)
    Q_PROPERTY(float   eoZoom        READ eoZoom        NOTIFY gimbalStateChanged)
    Q_PROPERTY(int     irZoom        READ irZoom        NOTIFY gimbalStateChanged)
    Q_PROPERTY(int     videoSource   READ videoSource   NOTIFY gimbalStateChanged)
    Q_PROPERTY(bool    recording     READ recording     NOTIFY gimbalStateChanged)
    Q_PROPERTY(int     trackState    READ trackState    NOTIFY gimbalStateChanged)
    Q_PROPERTY(float   laserRange    READ laserRange    NOTIFY gimbalStateChanged)

public:
    explicit ViewLinkController(QObject *parent = nullptr);
    ~ViewLinkController();

    static ViewLinkController *instance();

    // Property accessors
    bool  connected()   const { return _connected; }
    float gimbalPitch() const { return _gimbalPitch; }
    float gimbalYaw()   const { return _gimbalYaw; }
    float gimbalRoll()  const { return _gimbalRoll; }
    float eoZoom()      const { return _eoZoom; }
    int   irZoom()      const { return _irZoom; }
    int   videoSource() const { return _videoSource; }
    bool  recording()   const { return _recording; }
    int   trackState()  const { return _trackState; }
    float laserRange()  const { return _laserRange; }

    // Connection
    Q_INVOKABLE void connectToCamera(const QString &host, int port = 2000);
    Q_INVOKABLE void disconnectCamera();

    // Camera
    Q_INVOKABLE void takePhoto();
    Q_INVOKABLE void startRecord();
    Q_INVOKABLE void stopRecord();
    Q_INVOKABLE void zoomIn(int speed = 3);
    Q_INVOKABLE void zoomOut(int speed = 3);
    Q_INVOKABLE void zoomStop();
    Q_INVOKABLE void setZoomEO(int magnification10x);
    Q_INVOKABLE void setZoomIR(int magnification10x);
    Q_INVOKABLE void autoFocus();
    Q_INVOKABLE void manualFocusIn();
    Q_INVOKABLE void manualFocusOut();
    Q_INVOKABLE void focusStop();

    // Video source
    Q_INVOKABLE void setVideoSource(int source);

    // Gimbal
    Q_INVOKABLE void gimbalSpeed(float yawDegS, float pitchDegS);
    Q_INVOKABLE void gimbalAngle(float yawDeg, float pitchDeg);
    Q_INVOKABLE void gimbalHome();
    Q_INVOKABLE void gimbalLock();
    Q_INVOKABLE void gimbalFollow();
    Q_INVOKABLE void gimbalDown();

    // Tracking
    Q_INVOKABLE void trackPoint(float screenX, float screenY);
    Q_INVOKABLE void trackStop();
    Q_INVOKABLE void trackOpen();
    Q_INVOKABLE void setTrackBoxSize(int size);

    // Thermal
    Q_INVOKABLE void setColorPalette(int mode);

    // Laser
    Q_INVOKABLE void laserRangeOnce();
    Q_INVOKABLE void laserRangeContinuous();
    Q_INVOKABLE void laserRangeStop();

    // Query
    Q_INVOKABLE void queryGimbalState();

signals:
    void connectedChanged();
    void gimbalStateChanged();

private slots:
    void _onConnected();
    void _onDisconnected();
    void _onReadyRead();
    void _onSocketError(QAbstractSocket::SocketError error);

private:
    void _sendCmd(uint8_t b1, uint8_t b2, uint8_t b3, uint8_t b4, uint8_t b5);
    void _parseEEResponse(const QByteArray &packet);
    void _tryParseBuffer();

    QTcpSocket *_socket          = nullptr;
    QTimer      _reconnectTimer;
    QByteArray  _rxBuffer;

    QString     _host;
    int         _port            = 2000;

    // Connection state
    bool        _connected       = false;

    // Gimbal state from EE feedback
    float       _gimbalPitch     = 0.0f;
    float       _gimbalYaw       = 0.0f;
    float       _gimbalRoll      = 0.0f;
    float       _eoZoom          = 1.0f;
    int         _irZoom          = 1;
    int         _videoSource     = 0;
    bool        _recording       = false;
    int         _trackState      = 0;
    float       _laserRange      = 0.0f;

    // EE response parser
    static constexpr uint8_t EE_HEAD = 0xEE;
    enum ParseState { IDLE, EE_GOT_HEAD, EE_GOT_TYPE, EE_COLLECTING };
    ParseState  _parseState      = IDLE;
    uint8_t     _eeLen           = 0;
    QByteArray  _parsePacket;
};
