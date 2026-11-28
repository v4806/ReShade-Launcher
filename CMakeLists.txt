cmake_minimum_required(VERSION 3.25)

cmake_policy(SET CMP0077 NEW)
cmake_policy(SET CMP0091 NEW)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(version)

project(
    ReShadeLauncher
    VERSION ${RESHADE_LAUNCHER_VERSION}
    LANGUAGES C CXX RC
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)

if(MSVC)
    add_compile_options(
        /W4
        /permissive-
        /utf-8
        /EHsc
        /Zc:__cplusplus
    )
else()
    message(FATAL_ERROR "ReShade Launcher currently requires MSVC.")
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

set(APP_ICON_PATH "${CMAKE_CURRENT_SOURCE_DIR}/icon.ico")
file(TO_CMAKE_PATH "${APP_ICON_PATH}" APP_ICON_RC_PATH)

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/version.h.in"
    "${GENERATED_DIR}/version.h"
    @ONLY
)

set(VERSION_RC_PRODUCT_NAME "ReShade Launcher")
set(VERSION_RC_COMPANY_NAME "ReShade Launcher")
set(VERSION_RC_LEGAL_COPYRIGHT "Copyright (C) 2026 ReShade Launcher")
set(VERSION_RC_FILE_VERSION "${PROJECT_VERSION_MAJOR},${PROJECT_VERSION_MINOR},${PROJECT_VERSION_PATCH},${RESHADE_LAUNCHER_VERSION_TWEAK}")
set(VERSION_RC_PRODUCT_VERSION "${VERSION_RC_FILE_VERSION}")
set(VERSION_RC_INTERNAL_NAME "ReShadeLauncher")
set(VERSION_RC_ORIGINAL_FILENAME "ReShade Launcher Build.exe")
set(VERSION_RC_FILE_DESCRIPTION "ReShade Launcher")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/version.rc.in"
    "${GENERATED_DIR}/launcher_version.rc"
    @ONLY
)

set(VERSION_RC_INTERNAL_NAME "ReShadeLauncherDebug")
set(VERSION_RC_ORIGINAL_FILENAME "ReShade Debug.exe")
set(VERSION_RC_FILE_DESCRIPTION "ReShade Launcher Debug")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/version.rc.in"
    "${GENERATED_DIR}/debug_version.rc"
    @ONLY
)

set(VERSION_RC_INTERNAL_NAME "ReShadeLauncherUpdater")
set(VERSION_RC_ORIGINAL_FILENAME "ReShadeLauncherUpdater.exe")
set(VERSION_RC_FILE_DESCRIPTION "ReShade Launcher Updater")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/version.rc.in"
    "${GENERATED_DIR}/updater_version.rc"
    @ONLY
)

set(SOURCE_FILE_PATTERNS
    "*.c"
    "*.cc"
    "*.cpp"
    "*.cxx"
    "*.h"
    "*.hh"
    "*.hpp"
    "*.hxx"
)

set(RESHADE_LAUNCHER_SOURCES)
foreach(pattern IN LISTS SOURCE_FILE_PATTERNS)
    file(
        GLOB_RECURSE matched_sources
        CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/${pattern}"
    )
    list(APPEND RESHADE_LAUNCHER_SOURCES ${matched_sources})
endforeach()
list(
    FILTER RESHADE_LAUNCHER_SOURCES
    EXCLUDE REGEX "[/\\\\]src[/\\\\](updater|tests)[/\\\\]"
)

set(RESHADE_LAUNCHER_UPDATER_SOURCES)
foreach(pattern IN LISTS SOURCE_FILE_PATTERNS)
    file(
        GLOB_RECURSE matched_sources
        CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/updater/${pattern}"
    )
    list(APPEND RESHADE_LAUNCHER_UPDATER_SOURCES ${matched_sources})
endforeach()
list(
    APPEND RESHADE_LAUNCHER_UPDATER_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/src/update/update_client.cpp"
)

if(NOT RESHADE_LAUNCHER_SOURCES)
    message(
        FATAL_ERROR
        "No launcher sources found under src/. "
        "Add a Win32 GUI entry point and provide the ReShadeLauncher implementation."
    )
endif()

if(NOT RESHADE_LAUNCHER_UPDATER_SOURCES)
    message(
        FATAL_ERROR
        "No updater sources found under src/updater/. "
        "Add a Win32 entry point for ReShadeLauncherUpdater."
    )
endif()

set(WINDOWS_DEPENDENCIES
    d2d1
    dwrite
    dwmapi
    windowscodecs
    msimg32
    shlwapi
    shcore
    comctl32
    uxtheme
    shell32
    ole32
    oleaut32
    winhttp
    bcrypt
    crypt32
    wintrust
    version
    uuid
    user32
    gdi32
)

add_library(
    ReShadeLauncherMiniz
    STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz/miniz.c"
)
target_include_directories(
    ReShadeLauncherMiniz
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz"
)
target_compile_definitions(
    ReShadeLauncherMiniz
    PRIVATE
        _CRT_SECURE_NO_WARNINGS
)
if(MSVC)
    target_compile_options(ReShadeLauncherMiniz PRIVATE /W0)
endif()

add_executable(
    ReShadeLauncher
    WIN32
    ${RESHADE_LAUNCHER_SOURCES}
    "${GENERATED_DIR}/launcher_version.rc"
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/app.manifest.rc"
)
set_target_properties(
    ReShadeLauncher
    PROPERTIES
        OUTPUT_NAME "ReShade Launcher Build"
        VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_include_directories(
    ReShadeLauncher
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz"
        "${GENERATED_DIR}"
)
target_compile_definitions(
    ReShadeLauncher
    PRIVATE
        UNICODE
        _UNICODE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
)
target_link_libraries(
    ReShadeLauncher
    PRIVATE
        ReShadeLauncherMiniz
        ${WINDOWS_DEPENDENCIES}
)
target_link_options(
    ReShadeLauncher
    PRIVATE
        "/MANIFEST:NO"
)

add_executable(
    ReShadeLauncherDebug
    ${RESHADE_LAUNCHER_SOURCES}
    "${GENERATED_DIR}/debug_version.rc"
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/app.manifest.rc"
)
set_target_properties(
    ReShadeLauncherDebug
    PROPERTIES
        OUTPUT_NAME "ReShade Debug"
        VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_include_directories(
    ReShadeLauncherDebug
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz"
        "${GENERATED_DIR}"
)
target_compile_definitions(
    ReShadeLauncherDebug
    PRIVATE
        UNICODE
        _UNICODE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
        RESHADE_LAUNCHER_DEBUG_BUILD=1
)
target_compile_options(ReShadeLauncherDebug PRIVATE /Zi)
target_link_libraries(
    ReShadeLauncherDebug
    PRIVATE
        ReShadeLauncherMiniz
        ${WINDOWS_DEPENDENCIES}
)
target_link_options(
    ReShadeLauncherDebug
    PRIVATE
        "/MANIFEST:NO"
        "/DEBUG"
)

add_executable(
    ReShadeLauncherUpdater
    ${RESHADE_LAUNCHER_UPDATER_SOURCES}
    "${GENERATED_DIR}/updater_version.rc"
    "${CMAKE_CURRENT_SOURCE_DIR}/packaging/app.manifest.rc"
)
set_target_properties(
    ReShadeLauncherUpdater
    PROPERTIES
        OUTPUT_NAME "ReShadeLauncherUpdater"
        VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_include_directories(
    ReShadeLauncherUpdater
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/updater"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz"
        "${GENERATED_DIR}"
)
target_compile_definitions(
    ReShadeLauncherUpdater
    PRIVATE
        UNICODE
        _UNICODE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
)
target_link_libraries(
    ReShadeLauncherUpdater
    PRIVATE
        ReShadeLauncherMiniz
        ${WINDOWS_DEPENDENCIES}
)
target_link_options(
    ReShadeLauncherUpdater
    PRIVATE
        "/MANIFEST:NO"
)

source_group(
    TREE "${CMAKE_CURRENT_SOURCE_DIR}/src"
    FILES ${RESHADE_LAUNCHER_SOURCES} ${RESHADE_LAUNCHER_UPDATER_SOURCES}
)

set_property(DIRECTORY PROPERTY VS_STARTUP_PROJECT ReShadeLauncher)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/3dmloader.dll")
    foreach(target IN ITEMS ReShadeLauncher ReShadeLauncherDebug ReShadeLauncherUpdater)
        add_custom_command(
            TARGET ${target}
            POST_BUILD
            COMMAND
                "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_SOURCE_DIR}/3dmloader.dll"
                "$<TARGET_FILE_DIR:${target}>/3dmloader.dll"
            VERBATIM
        )
    endforeach()
endif()

include(CTest)
if(BUILD_TESTING AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/core_tests.cpp")
    add_executable(
        ReShadeLauncherCoreTests
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/core_tests.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/core/common.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/game/game.cpp"
    )
    target_include_directories(
        ReShadeLauncherCoreTests
        PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
            "${CMAKE_CURRENT_SOURCE_DIR}/third_party"
            "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz"
            "${GENERATED_DIR}"
    )
    target_compile_definitions(
        ReShadeLauncherCoreTests
        PRIVATE
            UNICODE
            _UNICODE
            WIN32_LEAN_AND_MEAN
            NOMINMAX
    )
    target_link_libraries(
        ReShadeLauncherCoreTests
        PRIVATE
            ReShadeLauncherMiniz
            ${WINDOWS_DEPENDENCIES}
    )
    add_test(NAME ReShadeLauncherCoreTests COMMAND ReShadeLauncherCoreTests)
elseif(BUILD_TESTING AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt")
    add_subdirectory(tests)
endif()

install(
    TARGETS ReShadeLauncher ReShadeLauncherDebug ReShadeLauncherUpdater
    RUNTIME DESTINATION .
)
