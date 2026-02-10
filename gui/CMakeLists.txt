cmake_minimum_required(VERSION 3.21)

project(JarvisHUD LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick WebSockets)

qt_standard_project_setup()

qt_add_executable(JarvisHUD
    main.cpp
    websocketclient.h
    websocketclient.cpp
)

qt_add_qml_module(JarvisHUD
    URI JarvisHUD
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/HudPanel.qml
        qml/AttentionView.qml
        qml/MLPView.qml
        qml/TokenStream.qml
        qml/TopKWheel.qml
)

target_link_libraries(JarvisHUD PRIVATE Qt6::Quick Qt6::WebSockets)

