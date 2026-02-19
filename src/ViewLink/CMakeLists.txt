target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        ViewLinkController.cc
        ViewLinkController.h
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE Qt6::Network)
