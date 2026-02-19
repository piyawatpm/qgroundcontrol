#include "GStreamerHelpers.h"

#include <gst/rtsp/gstrtspurl.h>
#include <QtCore/QLoggingCategory>
#include <QtCore/QString>
#include <QtCore/QStringList>

Q_DECLARE_LOGGING_CATEGORY(GStreamerLog)

namespace GStreamer
{

gboolean
is_valid_rtsp_uri(const gchar *uri_str)
{
    GstRTSPUrl *url = NULL;
    GstRTSPResult res;

    if (!gst_uri_is_valid(uri_str)) {
        return FALSE;
    }

    res = gst_rtsp_url_parse(uri_str, &url);
    if ((res != GST_RTSP_OK) || (url == NULL)) {
        return FALSE;
    }

    gst_rtsp_url_free(url);
    return TRUE;
}

bool is_hardware_decoder_factory(GstElementFactory *factory)
{
    if (!factory) {
        return false;
    }

    const gchar *factoryName = gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory));
    if (!factoryName) {
        return false;
    }

    // Exclude Android software decoders (OMXGoogle / C2Android)
    QString name = QString::fromUtf8(factoryName).toLower();
    if (name.startsWith("amcviddec-omxgoogle") || name.startsWith("amcviddec-c2android")) {
        qCWarning(GStreamerLog) << "  HW check:" << factoryName << "-> SOFTWARE (excluded Android SW wrapper)";
        return false;
    }

    const gchar *metaKlass = gst_element_factory_get_metadata(factory, GST_ELEMENT_METADATA_KLASS);
    const gchar *factoryKlass = gst_element_factory_get_klass(factory);

    const auto containsHardware = [](const gchar *value) {
        return value && (g_strrstr(value, "Hardware") != nullptr || g_strrstr(value, "hardware") != nullptr);
    };

    if (containsHardware(metaKlass)) {
        qCWarning(GStreamerLog) << "  HW check:" << factoryName << "-> HARDWARE (metadata klass:" << metaKlass << ")";
        return true;
    }

    if (containsHardware(factoryKlass)) {
        qCWarning(GStreamerLog) << "  HW check:" << factoryName << "-> HARDWARE (factory klass:" << factoryKlass << ")";
        return true;
    }

    const QString nameLower = QString::fromUtf8(factoryName).toLower();
    static const QStringList kHardwareTags = {
        QStringLiteral("va"),      // vaapi family
        QStringLiteral("nv"),      // nvidia nvcodec
        QStringLiteral("qsv"),     // intel quick sync
        QStringLiteral("msdk"),    // intel media sdk
        QStringLiteral("vulkan"),  // vulkan accelerated
        QStringLiteral("d3d"),     // direct3d
        QStringLiteral("dxva"),    // directx video accel
        QStringLiteral("vtdec"),   // apple video toolbox
        QStringLiteral("metal"),   // metal-based decoders
        QStringLiteral("amc")      // android mediacodec (amcviddec-*)
    };

    for (const QString &tag : kHardwareTags) {
        if (nameLower.startsWith(tag)) {
            qCWarning(GStreamerLog) << "  HW check:" << factoryName << "-> HARDWARE (name prefix:" << tag << ")";
            return true;
        }
    }

    qCWarning(GStreamerLog) << "  HW check:" << factoryName << "-> SOFTWARE (no match, klass:" << factoryKlass << ")";
    return false;
}

} // namespace GStreamer
