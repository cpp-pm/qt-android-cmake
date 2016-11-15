# Copyright (c) 2015, Ruslan Baratov
# All rights reserved.

# Hunterized version of https://github.com/LaurentGomila/qt-android-cmake
# Hunter package manager: https://github.com/ruslo/hunter

cmake_minimum_required(VERSION 3.0)
cmake_policy(SET CMP0026 OLD) # allow use of the LOCATION target property

if(NOT HUNTER_ENABLED)
  # Since it's not a project but CMake module for other projects we can't use
  # HunterGate command ('project' is the requirement). Just check we use Hunter
  # and add some stubs if not.

  function(hunter_add_package)
    # Do nothing
  endfunction()

  function(hunter_status_debug)
    message(STATUS ${ARGV})
  endfunction()

  function(hunter_internal_error)
    message(FATAL_ERROR ${ARGV})
  endfunction()

  function(hunter_user_error)
    message(FATAL_ERROR ${ARGV})
  endfunction()
endif()

if(XCODE OR MSVC_IDE)
  hunter_user_error(
      "Only for single-configuration generators (like 'Unix Makefiles')"
  )
endif()

# store the current source directory for future use
set(QT_ANDROID_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# make sure that the Android toolchain is used
if(NOT ANDROID)
  hunter_internal_error(
      "Trying to use the CMake Android package without the Android toolchain."
  )
endif()

hunter_add_package(Qt COMPONENTS qttools) # androiddeployqt
find_package(Qt5Core REQUIRED)

get_filename_component(QT_ANDROID_QT_ROOT "${Qt5Core_DIR}/../../.." ABSOLUTE)
hunter_status_debug("Found Qt for Android: ${QT_ANDROID_QT_ROOT}")

# find the Android SDK
if(HUNTER_ENABLED)
  hunter_add_package(Android-SDK)
  set(QT_ANDROID_SDK_ROOT "${ANDROID-SDK_ROOT}/android-sdk")
endif()

if(NOT QT_ANDROID_SDK_ROOT)
  set(QT_ANDROID_SDK_ROOT "$ENV{ANDROID_SDK}")
  if(NOT QT_ANDROID_SDK_ROOT)
    hunter_internal_error(
        "Could not find the Android SDK. Please set either the ANDROID_SDK"
        " environment variable, or the QT_ANDROID_SDK_ROOT CMake variable to"
        " the root directory of the Android SDK"
    )
  endif()
endif()

# androiddeployqt doesn't like backslashes in paths
string(REPLACE "\\" "/" QT_ANDROID_SDK_ROOT "${QT_ANDROID_SDK_ROOT}")

hunter_status_debug("Found Android SDK: ${QT_ANDROID_SDK_ROOT}")

string(COMPARE EQUAL "${ANDROID_NDK}" "" _is_empty)
if(HUNTER_ENABLED)
  if(_is_empty)
    hunter_internal_error("ANDROID_NDK is not set")
  endif()
  set(QT_ANDROID_NDK_ROOT "${ANDROID_NDK}")
endif()

# find the Android NDK
if(NOT QT_ANDROID_NDK_ROOT)
  set(QT_ANDROID_NDK_ROOT "$ENV{ANDROID_NDK}")
  if(NOT QT_ANDROID_NDK_ROOT)
    set(QT_ANDROID_NDK_ROOT "${ANDROID_NDK}")
    if(NOT QT_ANDROID_NDK_ROOT)
      hunter_internal_error(
          "Could not find the Android NDK. Please set either the ANDROID_NDK"
          " environment or CMake variable, or the QT_ANDROID_NDK_ROOT CMake"
          " variable to the root directory of the Android NDK"
      )
    endif()
  endif()
endif()

# androiddeployqt doesn't like backslashes in paths
string(REPLACE "\\" "/" QT_ANDROID_NDK_ROOT "${QT_ANDROID_NDK_ROOT}")

hunter_status_debug("Found Android NDK: ${QT_ANDROID_NDK_ROOT}")

# find ANT
if(NOT QT_ANDROID_ANT)
  set(QT_ANDROID_ANT "$ENV{ANT}")
  if(NOT QT_ANDROID_ANT)
    find_host_program(QT_ANDROID_ANT NAME ant)
    if(NOT QT_ANDROID_ANT)
      if(CMAKE_HOST_WIN32)
        set(_which_command where)
      else()
        set(_which_command which)
      endif()
      execute_process(
          COMMAND ${_which_command} ant
          RESULT_VARIABLE _which_result
          OUTPUT_VARIABLE QT_ANDROID_ANT
              # TODO: windows can output several paths
          OUTPUT_STRIP_TRAILING_WHITESPACE
      )
      if(NOT _which_result EQUAL 0)
        hunter_internal_error(
            "Could not find ANT. Please add its directory to the PATH"
            " environment variable, or set the ANT environment variable or"
            " QT_ANDROID_ANT CMake variable to its path."
        )
      endif()
    endif()
  endif()
endif()
hunter_status_debug("Found ANT: ${QT_ANDROID_ANT}")

include(CMakeParseArguments)

# define a macro to create an Android APK target
#
# example:
# add_library(my_app SHARED ...)
# add_qt_android_apk(
#     TARGET my_app_apk
#     BASE_TARGET my_app
#     LAUNCH_TARGET launch_my_app
#     NAME "My App"
#     PACKAGE_NAME "org.mycompany.myapp"
#     PACKAGE_SOURCES ${CMAKE_CURRENT_LIST_DIR}/my-android-sources
#     KEYSTORE ${CMAKE_CURRENT_LIST_DIR}/mykey.keystore myalias
#     KEYSTORE_PASSWORD xxxx
#     MANIFEST "/path/to/AndroidManifest.xml.in"
#     DEPENDS a_linked_target "path/to/a_linked_library.so" ...
#     QML_ROOT "/path/to/directory/with/qml/files"
#     INSTALL
# )
#
function(add_qt_android_apk)
  if(NOT ANDROID)
    hunter_user_error("ANDROID is empty")
  endif()

  if(ANDROID AND CMAKE_VERSION VERSION_LESS "3.7")
    message(FATAL_ERROR "CMake version 3.7+ required")
  endif()

  string(COMPARE EQUAL "${CMAKE_SYSTEM_VERSION}" "" is_empty)
  if(is_empty)
    hunter_user_error("CMAKE_SYSTEM_VERSION is empty")
  endif()

  # parse the macro arguments
  cmake_parse_arguments(
      ARG
      "INSTALL"
      "TARGET;BASE_TARGET;LAUNCH_TARGET;NAME;PACKAGE_NAME;PACKAGE_SOURCES;KEYSTORE_PASSWORD;MANIFEST;QML_ROOT"
      "DEPENDS;KEYSTORE"
      ${ARGN}
  )
  # ->
  #   * ARG_INSTALL
  #   * ARG_TARGET
  #   * ARG_BASE_TARGET
  #   * ARG_LAUNCH_TARGET
  #   * ARG_NAME
  #   * ARG_PACKAGE_NAME
  #   * ARG_PACKAGE_SOURCES
  #   * ARG_KEYSTORE_PASSWORD
  #   * ARG_MANIFEST
  #   * ARG_QML_ROOT
  #   * ARG_DEPENDS
  #   * ARG_KEYSTORE

  string(COMPARE NOTEQUAL "${ARG_UNPARSED_ARGUMENTS}" "" has_unparsed)
  if(has_unparsed)
    hunter_user_error("Unparsed arguments: ${ARG_UNPARSED_ARGUMENTS}")
  endif()

  string(COMPARE EQUAL "${ARG_TARGET}" "" is_empty)
  if(is_empty)
    hunter_user_error("TARGET is mandatory")
  endif()

  string(COMPARE EQUAL "${ARG_BASE_TARGET}" "" is_empty)
  if(is_empty)
    hunter_user_error("BASE_TARGET is mandatory")
  endif()

  if(NOT TARGET "${ARG_BASE_TARGET}")
    hunter_user_error("Is not a target: ${ARG_BASE_TARGET}")
  endif()

  if(TARGET "${ARG_TARGET}")
    hunter_user_error("Target already exists: ${ARG_TARGET}")
  endif()

  string(COMPARE EQUAL "${CMAKE_BUILD_TYPE}" "Debug" is_debug)

  # check the configuration
  if(is_debug)
    set(ANT_CONFIG debug)
  else()
    set(ANT_CONFIG release)
  endif()

  # extract the full path of the source target binary
  if(is_debug)
    get_property(
        QT_ANDROID_APP_PATH TARGET "${ARG_BASE_TARGET}" PROPERTY DEBUG_LOCATION
    )
  else()
    get_property(
        QT_ANDROID_APP_PATH TARGET "${ARG_BASE_TARGET}" PROPERTY LOCATION
    )
  endif()

  # define the application name
  string(COMPARE NOTEQUAL "${ARG_NAME}" "" has_name)
  if(has_name)
    set(QT_ANDROID_APP_NAME "${ARG_NAME}")
  else()
    set(QT_ANDROID_APP_NAME "${ARG_BASE_TARGET}")
  endif()

  # define the application package name
  string(COMPARE NOTEQUAL "${ARG_PACKAGE_NAME}" "" has_package_name)
  if(has_package_name)
    set(QT_ANDROID_APP_PACKAGE_NAME "${ARG_PACKAGE_NAME}")
  else()
    set(QT_ANDROID_APP_PACKAGE_NAME "org.qtproject.${ARG_BASE_TARGET}")
  endif()

  # define the application source package directory
  string(COMPARE NOTEQUAL "${ARG_PACKAGE_SOURCES}" "" has_package_sources)
  if(has_package_sources)
    set(QT_ANDROID_APP_PACKAGE_SOURCE_ROOT "${ARG_PACKAGE_SOURCES}")
  else()
    # get app version
    get_property(
        QT_ANDROID_APP_VERSION TARGET "${ARG_BASE_TARGET}" PROPERTY VERSION
    )

    # use the major version number for code version (must be a single number)
    string(
        REGEX
        MATCH
        "[0-9]+"
        QT_ANDROID_APP_VERSION_CODE
        "${QT_ANDROID_APP_VERSION}"
    )

    string(COMPARE EQUAL "${QT_ANDROID_APP_VERSION_CODE}" "" is_empty)
    if(is_empty)
      hunter_user_error(
          "Empty version not allowed. Please set VERSION property to target:"
          "  ${ARG_BASE_TARGET}"
      )
    endif()

    # create a subdirectory for the extra package sources
    set(
        QT_ANDROID_APP_PACKAGE_SOURCE_ROOT
        "${CMAKE_CURRENT_BINARY_DIR}/package"
    )

    string(COMPARE EQUAL "${ARG_MANIFEST}" "" is_empty)
    if(is_empty)
      set(
          manifest_source
          "${QT_ANDROID_SOURCE_DIR}/templates/AndroidManifest.xml.in"
      )
    else()
      set(manifest_source "${ARG_MANIFEST}")
    endif()

    if(NOT EXISTS "${manifest_source}")
      hunter_user_error("File not exists: ${manifest_source}")
    endif()

    # generate a manifest from the template
    # Use:
    #   CMAKE_SYSTEM_VERSION
    #   QT_ANDROID_APP_NAME
    #   QT_ANDROID_APP_PACKAGE_NAME
    #   QT_ANDROID_APP_VERSION
    #   QT_ANDROID_APP_VERSION_CODE
    configure_file(
        "${manifest_source}"
        "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/AndroidManifest.xml"
        @ONLY
    )
  endif()

  # set the list of dependant libraries
  set(EXTRA_LIBS "")
  foreach(LIB ${ARG_DEPENDS})
    if(TARGET "${LIB}")
      # item is a CMake target, extract the library path
      if(is_debug)
        get_property(LIB_PATH TARGET "${LIB}" PROPERTY DEBUG_LOCATION)
      else()
        get_property(LIB_PATH TARGET "${LIB}" PROPERTY LOCATION)
      endif()
      set(LIB "${LIB_PATH}")
    endif()
    string(COMPARE NOTEQUAL "${EXTRA_LIBS}" "" has_extra_libs)
    if(has_extra_libs)
      set(EXTRA_LIBS "${EXTRA_LIBS},${LIB}")
    else()
      set(EXTRA_LIBS "${LIB}")
    endif()
  endforeach()

  string(COMPARE NOTEQUAL "${EXTRA_LIBS}" "" has_extra_libs)
  if(has_extra_libs)
    set(QT_ANDROID_APP_EXTRA_LIBS "\"android-extra-libs\": \"${EXTRA_LIBS}\",")
  endif()

  string(COMPARE NOTEQUAL "${ARG_QML_ROOT}" "" has_qml_root)
  if(has_qml_root)
    if(NOT EXISTS "${ARG_QML_ROOT}")
      hunter_user_error("Directory not exists (QML_ROOT): ${ARG_QML_ROOT}")
    endif()
    if(NOT IS_DIRECTORY "${ARG_QML_ROOT}")
      hunter_user_error("Is not a directory (QML_ROOT): ${ARG_QML_ROOT}")
    endif()
    set(QT_QML_ROOT "\"qml-root-path\": \"${ARG_QML_ROOT}\",")
  endif()

  string(COMPARE EQUAL "${CMAKE_CXX_ANDROID_TOOLCHAIN_MACHINE}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "CMAKE_CXX_ANDROID_TOOLCHAIN_MACHINE is empty")
  endif()

  string(COMPARE EQUAL "${ANDROID_COMPILER_VERSION}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "ANDROID_COMPILER_VERSION is empty")
  endif()

  string(COMPARE EQUAL "${CMAKE_ANDROID_ARCH_ABI}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "CMAKE_ANDROID_ARCH_ABI is empty")
  endif()

  string(COMPARE EQUAL "${ANDROID_NDK_HOST_SYSTEM_NAME}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "ANDROID_NDK_HOST_SYSTEM_NAME is empty")
  endif()

  # create the configuration file that will feed androiddeployqt
  # Used variables:
  #   * ANDROID_COMPILER_VERSION
  #   * ANDROID_NDK_HOST_SYSTEM_NAME
  #   * CMAKE_CXX_ANDROID_TOOLCHAIN_MACHINE
  #   * CMAKE_ANDROID_ARCH_ABI
  #   * QT_ANDROID_APP_EXTRA_LIBS
  #   * QT_ANDROID_APP_NAME
  #   * QT_ANDROID_APP_PACKAGE_NAME
  #   * QT_ANDROID_APP_PACKAGE_SOURCE_ROOT
  #   * QT_ANDROID_APP_PATH
  #   * QT_ANDROID_NDK_ROOT
  #   * QT_ANDROID_QT_ROOT
  #   * QT_ANDROID_SDK_ROOT
  #   * QT_QML_ROOT
  configure_file(
      "${QT_ANDROID_SOURCE_DIR}/templates/qtdeploy.json.in"
      "${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json"
      @ONLY
  )

  # check if the apk must be signed
  string(COMPARE NOTEQUAL "${ARG_KEYSTORE}" "" has_keystore)
  string(COMPARE NOTEQUAL "${ARG_KEYSTORE_PASSWORD}" "" has_keystore_password)
  set(SIGN_OPTIONS "")

  if(has_keystore)
    set(
        SIGN_OPTIONS
        --release
        --sign
        "${ARG_KEYSTORE}"
        --tsa
        "http://timestamp.digicert.com"
    )
    if(has_keystore_password)
      list(APPEND SIGN_OPTIONS "--storepass" "${ARG_KEYSTORE_PASSWORD}")
    endif()
  endif()

  # check if the apok must be installed to the device
  if(ARG_INSTALL)
    set(INSTALL_OPTIONS --install)
  else()
    set(INSTALL_OPTIONS "")
  endif()

  # create a custom command that will run the androiddeployqt utility
  # to prepare the Android package
  # make sure that the output directory for the Android package exists
  set(dst "${CMAKE_CURRENT_BINARY_DIR}/libs/${CMAKE_ANDROID_ARCH_ABI}")
  file(MAKE_DIRECTORY "${dst}")

  set(dummy_output_apk "run_android_deploy_qt_${ARG_BASE_TARGET}")
  add_custom_command(
      OUTPUT ${dummy_output_apk}
      DEPENDS "${ARG_BASE_TARGET}"
      COMMAND
          # it seems that recompiled libraries are not copied
          # if we don't remove them first
          "${CMAKE_COMMAND}"
          -E remove_directory "${dst}"
      COMMAND
          "${CMAKE_COMMAND}"
          -E make_directory "${dst}"
      COMMAND
          "${CMAKE_COMMAND}"
          -E copy
          "${QT_ANDROID_APP_PATH}"
          "${dst}"
      COMMAND
          "${QT_ANDROID_QT_ROOT}/bin/androiddeployqt"
          --verbose
          --output "${CMAKE_CURRENT_BINARY_DIR}"
          --input "${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json"
          --ant "${QT_ANDROID_ANT}"
          --android-platform "android-${CMAKE_SYSTEM_VERSION}"
          ${INSTALL_OPTIONS}
          ${SIGN_OPTIONS}
      COMMENT "Creating APK (target: ${ARG_TARGET} base: ${ARG_BASE_TARGET})"
  )

  # create the custom target that invokes ANT to create the apk
  add_custom_target(
      ${ARG_TARGET}
      ALL
      COMMAND "${QT_ANDROID_ANT}" "${ANT_CONFIG}"
      DEPENDS ${dummy_output_apk}
  )

  string(COMPARE NOTEQUAL "${ARG_LAUNCH_TARGET}" "" has_launch)
  if(has_launch)
    set(dummy_output_launch "run_android_launch_qt_${ARG_BASE_TARGET}")
    add_custom_command(
        OUTPUT ${dummy_output_launch}
        DEPENDS "${ARG_BASE_TARGET}"
        COMMAND
            # it seems that recompiled libraries are not copied
            # if we don't remove them first
            "${CMAKE_COMMAND}"
            -E remove_directory "${dst}"
        COMMAND
            "${CMAKE_COMMAND}"
            -E make_directory "${dst}"
        COMMAND
            "${CMAKE_COMMAND}"
            -E copy
            "${QT_ANDROID_APP_PATH}"
            "${dst}"
        COMMAND
            "${QT_ANDROID_QT_ROOT}/bin/androiddeployqt"
            --verbose
            --output "${CMAKE_CURRENT_BINARY_DIR}"
            --input "${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json"
            --ant "${QT_ANDROID_ANT}"
            --android-platform "android-${CMAKE_SYSTEM_VERSION}"
            --install
            ${SIGN_OPTIONS}
        COMMENT "Launching APK (target: ${ARG_TARGET} base: ${ARG_BASE_TARGET})"
    )

    # create the custom target that invokes ANT to launch the apk
    set(adb "${ANDROID-SDK_ROOT}/android-sdk/platform-tools/adb")
    set(activity "org.qtproject.qt5.android.bindings.QtActivity")
    add_custom_target(
        ${ARG_LAUNCH_TARGET}
        COMMAND "${QT_ANDROID_ANT}" "${ANT_CONFIG}"
        COMMAND
            "${adb}"
            shell
            am
            start
            -S
            -n "${QT_ANDROID_APP_PACKAGE_NAME}/${activity}"
        DEPENDS ${dummy_output_launch}
    )
  endif()
endfunction()
