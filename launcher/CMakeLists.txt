cmake_minimum_required(VERSION 3.21)

project(JarvisLauncher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Make the launcher more portable between PCs by linking the MSVC runtime statically.
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_executable(JarvisLauncher WIN32
  main.cpp
)

target_link_libraries(JarvisLauncher PRIVATE user32 shell32)

