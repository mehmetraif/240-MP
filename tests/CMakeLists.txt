cmake_minimum_required(VERSION 3.21)
project(osdos_regression_tests LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Concurrent Network Qml Test)
enable_testing()
add_executable(storage_search_test
    storage_search_test.cpp
    ../src/AppCore.cpp
    ../src/util/LegacyNames.cpp
    ../src/modules/local_files/LocalFilesBackend.cpp
    ../src/modules/local_files/RemovableDrives.cpp)
target_include_directories(storage_search_test PRIVATE ../src)
target_link_libraries(storage_search_test PRIVATE
    Qt6::Core Qt6::Concurrent Qt6::Network Qt6::Qml Qt6::Test)
add_test(NAME storage_search COMMAND storage_search_test)

# One video handed over to the next (MpvController), against a stand-in for
# mpv. Linux only: the stand-in is a shell script that looks in /proc.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    find_package(Qt6 REQUIRED COMPONENTS Gui Quick)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(Libdrm REQUIRED libdrm)
    add_executable(playback_retire_test
        playback_retire_test.cpp
        ../src/player/MpvController.cpp
        ../src/player/EmbeddedMpv.cpp
        ../src/AppCore.cpp
        ../src/audio/AudioOutput.cpp
        ../src/util/Board.cpp
        ../src/util/DisplayHandoff.cpp
        ../src/util/ExecPath.cpp
        ../src/util/FontconfigOverride.cpp
        ../src/util/LegacyNames.cpp
        ../src/util/MpvLocator.cpp
        ../src/util/YtDlpLocator.cpp)
    target_include_directories(playback_retire_test PRIVATE ../src ${Libdrm_INCLUDE_DIRS})
    target_link_libraries(playback_retire_test PRIVATE
        Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml Qt6::Network Qt6::Test ${Libdrm_LIBRARIES})
    add_test(NAME playback_retire COMMAND playback_retire_test)
endif()
