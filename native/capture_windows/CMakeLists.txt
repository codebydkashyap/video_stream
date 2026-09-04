cmake_minimum_required(VERSION 3.18)

# ─── Windows capture plugin ──────────────────────────────────────────────
project(capture_windows CXX)

add_library(capture_windows SHARED capture_windows.cpp)

target_compile_options(capture_windows PRIVATE /W4)
target_link_libraries(capture_windows PRIVATE dxgi d3d11)

set_target_properties(capture_windows PROPERTIES
    CXX_STANDARD 17
    OUTPUT_NAME "capture_windows"
)

install(TARGETS capture_windows RUNTIME DESTINATION .)
