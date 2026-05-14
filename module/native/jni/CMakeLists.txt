cmake_minimum_required(VERSION 3.18)
project(teesimplus LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(teesimplus SHARED
    main.cpp
    hook.cpp
    equalizer.cpp
)

target_include_directories(teesimplus PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(teesimplus
    log
    dl
)

target_compile_options(teesimplus PRIVATE
    -Wall -Wextra -O2 -fvisibility=hidden
)
