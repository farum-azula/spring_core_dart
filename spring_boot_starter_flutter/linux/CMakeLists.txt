# The Linux (GTK) part of spring_boot_starter_flutter: the desktop window's
# title bar, size and drag. It is written in plain C style, in a .cc file
# because the Flutter tool's standard settings build the plugin as C++.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "spring_boot_starter_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "spring_boot_starter_flutter_plugin")

list(APPEND PLUGIN_SOURCES
  "spring_boot_starter_flutter_plugin.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# List of absolute paths to libraries that should be bundled with the plugin.
set(spring_boot_starter_flutter_bundled_libraries
  ""
  PARENT_SCOPE
)
