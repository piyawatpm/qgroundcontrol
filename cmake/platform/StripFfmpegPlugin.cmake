# StripFfmpegPlugin.cmake
# Removes problematic plugin/lib references from the androiddeployqt JSON.
# Qt loader aborts if ANY listed lib fails to dlopen.

if(NOT EXISTS "${DEPLOY_JSON}")
    return()
endif()

find_package(Python3 QUIET COMPONENTS Interpreter)
if(NOT Python3_FOUND)
    find_program(Python3_EXECUTABLE NAMES python3 python)
endif()

if(Python3_EXECUTABLE)
    execute_process(
        COMMAND ${Python3_EXECUTABLE} -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
bad = ['ffmpeg','FFmpeg','WebView','webview','FluentWinUI3','Fusion','Imagine','Material','Universal']
for key in ['android-extra-libs','android-deploy-plugins']:
    if key not in d or not d[key]:
        continue
    sep = ',' if ',' in d[key] else ';'
    entries = [e for e in d[key].split(sep) if e and not any(b in e for b in bad)]
    d[key] = sep.join(entries)
with open(sys.argv[1],'w') as f:
    json.dump(d, f, indent=2)
print('Stripped problematic libs from', sys.argv[1])
" "${DEPLOY_JSON}"
        RESULT_VARIABLE _strip_result
    )
    if(NOT _strip_result EQUAL 0)
        message(WARNING "Failed to strip problematic libs from deploy JSON")
    endif()
else()
    message(WARNING "Python3 not found - cannot strip problematic libs from deploy JSON")
endif()
