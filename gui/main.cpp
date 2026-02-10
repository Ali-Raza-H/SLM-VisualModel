#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

#include "websocketclient.h"

int main(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);
  QCoreApplication::setApplicationName("JarvisHUD");

  WebSocketClient ws;

  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("ws", &ws);
  // Load the entrypoint directly from the embedded Qt resource.
  // (This avoids any mismatch between QML module prefixes and runtime import paths.)
  engine.load(QUrl(QStringLiteral("qrc:/JarvisHUD/qml/Main.qml")));

  if (engine.rootObjects().isEmpty()) {
    return -1;
  }
  return app.exec();
}
