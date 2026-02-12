# StripFfmpegPlugin.cmake
# Removes ffmpeg multimedia plugin references from the androiddeployqt JSON.
# Qt loader aborts if any listed plugin fails to dlopen, and ffmpeg requires
# libavformat/libavcodec which aren't bundled.

if(NOT EXISTS "${DEPLOY_JSON}")
    return()
endif()

file(READ "${DEPLOY_JSON}" _json_content)

# Remove ffmpeg plugin path entries from the semicolon-separated deploy-plugins list
string(REGEX REPLACE "[^;]*ffmpeg[^;]*;?" "" _json_content "${_json_content}")
# Clean up any trailing semicolons before the closing quote
string(REGEX REPLACE ";\"" "\"" _json_content "${_json_content}")

file(WRITE "${DEPLOY_JSON}" "${_json_content}")
message(STATUS "Stripped ffmpeg plugin references from ${DEPLOY_JSON}")
