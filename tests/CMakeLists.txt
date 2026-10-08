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
