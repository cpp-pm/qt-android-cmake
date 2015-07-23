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

# store the current source directory for future use
set(QT_ANDROID_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# make sure that the Android toolchain is used
if(NOT ANDROID)
  hunter_internal_error(
      "Trying to use the CMake Android package without the Android toolchain."
  )
endif()

hunter_add_package(Qt)
find_package(Qt5Core REQUIRED)

get_filename_component(QT_ANDROID_QT_ROOT "${Qt5Core_DIR}/../../.." ABSOLUTE)
hunter_status_debug("Found Qt for Android: ${QT_ANDROID_QT_ROOT}")

# find the Android SDK
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
    find_program(QT_ANDROID_ANT NAME ant)
    if(NOT QT_ANDROID_ANT)
      hunter_internal_error(
          "Could not find ANT. Please add its directory to the PATH environment"
          " variable, or set the ANT environment variable or QT_ANDROID_ANT"
          " CMake variable to its path."
      )
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
#     NAME "My App"
#     PACKAGE_NAME "org.mycompany.myapp"
#     PACKAGE_SOURCES ${CMAKE_CURRENT_LIST_DIR}/my-android-sources
#     KEYSTORE ${CMAKE_CURRENT_LIST_DIR}/mykey.keystore myalias
#     KEYSTORE_PASSWORD xxxx
#     DEPENDS a_linked_target "path/to/a_linked_library.so" ...
#     INSTALL
# )
#
function(add_qt_android_apk)
  # parse the macro arguments
  cmake_parse_arguments(
      ARG
      "INSTALL"
      "TARGET;BASE_TARGET;NAME;PACKAGE_NAME;PACKAGE_SOURCES;KEYSTORE_PASSWORD"
      "DEPENDS;KEYSTORE"
      ${ARGN}
  )

  # check the configuration
  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(ANT_CONFIG debug)
  else()
    set(ANT_CONFIG release)
  endif()

  # extract the full path of the source target binary
  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    get_property(
        QT_ANDROID_APP_PATH TARGET "${ARG_BASE_TARGET}" PROPERTY DEBUG_LOCATION
    )
  else()
    get_property(
        QT_ANDROID_APP_PATH TARGET "${ARG_BASE_TARGET}" PROPERTY LOCATION
    )
  endif()

  # define the application name
  if(ARG_NAME)
    set(QT_ANDROID_APP_NAME "${ARG_NAME}")
  else()
    set(QT_ANDROID_APP_NAME "${ARG_BASE_TARGET}")
  endif()

  # define the application package name
  if(ARG_PACKAGE_NAME)
    set(QT_ANDROID_APP_PACKAGE_NAME "${ARG_PACKAGE_NAME}")
  else()
    set(QT_ANDROID_APP_PACKAGE_NAME "org.qtproject.${ARG_BASE_TARGET}")
  endif()

  # define the application source package directory
  if(ARG_PACKAGE_SOURCES)
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

    # create a subdirectory for the extra package sources
    set(
        QT_ANDROID_APP_PACKAGE_SOURCE_ROOT
        "${CMAKE_CURRENT_BINARY_DIR}/package"
    )

    # generate a manifest from the template
    configure_file(
        "${QT_ANDROID_SOURCE_DIR}/AndroidManifest.xml.in"
        "${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/AndroidManifest.xml"
        @ONLY
    )
  endif()

  # set the list of dependant libraries
  if(ARG_DEPENDS)
    foreach(LIB ${ARG_DEPENDS})
      if(TARGET "${LIB}")
        # item is a CMake target, extract the library path
        if(CMAKE_BUILD_TYPE STREQUAL "Debug")
          get_property(LIB_PATH TARGET "${LIB}" PROPERTY DEBUG_LOCATION)
        else()
          get_property(LIB_PATH TARGET "${LIB}" PROPERTY LOCATION)
        endif()
        set(LIB "${LIB_PATH}")
      endif()
      if(EXTRA_LIBS)
        set(EXTRA_LIBS "${EXTRA_LIBS},${LIB}")
      else()
        set(EXTRA_LIBS "${LIB}")
      endif()
    endforeach()
    set(QT_ANDROID_APP_EXTRA_LIBS "\"android-extra-libs\": \"${EXTRA_LIBS}\",")
  endif()

  # make sure that the output directory for the Android package exists
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI}")

  # create the configuration file that will feed androiddeployqt
  configure_file(
      "${QT_ANDROID_SOURCE_DIR}/qtdeploy.json.in"
      "${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json"
      @ONLY
  )

  # check if the apk must be signed
  if(ARG_KEYSTORE)
    set(
        SIGN_OPTIONS
        --release
        --sign
        "${ARG_KEYSTORE}"
        --tsa
        "http://timestamp.digicert.com"
    )
    if(ARG_KEYSTORE_PASSWORD)
      set(SIGN_OPTIONS ${SIGN_OPTIONS} --storepass "${ARG_KEYSTORE_PASSWORD}")
    endif()
  endif()

  # check if the apok must be installed to the device
  if(ARG_INSTALL)
    set(INSTALL_OPTIONS --install)
  endif()

  # create a custom command that will run the androiddeployqt utility
  # to prepare the Android package
  add_custom_command(
      OUTPUT run_android_deploy_qt
      DEPENDS "${ARG_BASE_TARGET}"
      COMMAND
          # it seems that recompiled libraries are not copied
          # if we don't remove them first
          "${CMAKE_COMMAND}"
          -E remove_directory "${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI}"
      COMMAND
          "${CMAKE_COMMAND}"
          -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI}"
      COMMAND
          "${CMAKE_COMMAND}"
          -E copy
          "${QT_ANDROID_APP_PATH}"
          "${CMAKE_CURRENT_BINARY_DIR}/libs/${ANDROID_ABI}"
      COMMAND
          "${QT_ANDROID_QT_ROOT}/bin/androiddeployqt"
          --verbose
          --output "${CMAKE_CURRENT_BINARY_DIR}"
          --input "${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json"
          --ant "${QT_ANDROID_ANT}"
          ${INSTALL_OPTIONS}
          ${SIGN_OPTIONS}
  )

  # create the custom target that invokes ANT to create the apk
  add_custom_target(
      ${ARG_TARGET}
      ALL
      COMMAND "${QT_ANDROID_ANT}" "${ANT_CONFIG}"
      DEPENDS run_android_deploy_qt
  )
endfunction()
