cmake_minimum_required(VERSION 3.20)

project(render LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(USE_SYSTEM_SDL3 "Use SDL3 from the system (find_package) instead of fetching" OFF)

if(USE_SYSTEM_SDL3)
  find_package(SDL3 REQUIRED CONFIG)
else()
  include(FetchContent)
  FetchContent_Declare(
    SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG release-3.4.0
  )
  FetchContent_MakeAvailable(SDL3)
endif()

add_executable(render
  src/main.c
)

# SDL provides the SDL3::SDL3 target when built via CMake
target_link_libraries(render PRIVATE SDL3::SDL3)

# Helpful defaults
if(MSVC)
  target_compile_options(render PRIVATE /W4)
else()
  target_compile_options(render PRIVATE -Wall -Wextra -Wpedantic)
endif()
