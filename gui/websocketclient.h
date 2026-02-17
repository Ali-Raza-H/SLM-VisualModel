#pragma once

#include <QAbstractSocket>
#include <QElapsedTimer>
#include <QJsonValue>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QWebSocket>

class WebSocketClient : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

  Q_PROPERTY(QString generated READ generated NOTIFY generatedChanged)
  Q_PROPERTY(QStringList tokens READ tokens NOTIFY tokensChanged)

  Q_PROPERTY(QVariantList topk READ topk NOTIFY topkChanged)
  Q_PROPERTY(int sampledId READ sampledId NOTIFY sampledChanged)
  Q_PROPERTY(QString sampledToken READ sampledToken NOTIFY sampledChanged)
  Q_PROPERTY(double sampledProb READ sampledProb NOTIFY sampledChanged)

  Q_PROPERTY(int attentionLayer READ attentionLayer NOTIFY attentionChanged)
  Q_PROPERTY(int attentionHead READ attentionHead NOTIFY attentionChanged)
  Q_PROPERTY(QVariantList attentionMatrix READ attentionMatrix NOTIFY attentionChanged)

  Q_PROPERTY(int mlpLayer READ mlpLayer NOTIFY mlpChanged)
  Q_PROPERTY(QVariantList mlpActivations READ mlpActivations NOTIFY mlpChanged)

  Q_PROPERTY(int residualLayer READ residualLayer NOTIFY residualChanged)
  Q_PROPERTY(QVariantList residualNorms READ residualNorms NOTIFY residualChanged)
  Q_PROPERTY(QVariantList residualLayersLast READ residualLayersLast NOTIFY residualLayersLastChanged)

  Q_PROPERTY(QString device READ device NOTIFY metaChanged)
  Q_PROPERTY(bool done READ done NOTIFY metaChanged)
  Q_PROPERTY(QVariantMap meta READ meta NOTIFY metaChanged)

  Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

  Q_PROPERTY(QStringList logLines READ logLines NOTIFY logLinesChanged)
  Q_PROPERTY(QString lastJson READ lastJson NOTIFY lastJsonChanged)
  Q_PROPERTY(double lastRoundTripMs READ lastRoundTripMs NOTIFY perfChanged)
  Q_PROPERTY(int lastPayloadBytes READ lastPayloadBytes NOTIFY perfChanged)

public:
  explicit WebSocketClient(QObject *parent = nullptr);

  bool connected() const { return m_connected; }
  bool busy() const { return m_busy; }

  QString generated() const { return m_generated; }
  QStringList tokens() const { return m_tokens; }

  QVariantList topk() const { return m_topk; }
  int sampledId() const { return m_sampledId; }
  QString sampledToken() const { return m_sampledToken; }
  double sampledProb() const { return m_sampledProb; }

  int attentionLayer() const { return m_attentionLayer; }
  int attentionHead() const { return m_attentionHead; }
  QVariantList attentionMatrix() const { return m_attentionMatrix; }

  int mlpLayer() const { return m_mlpLayer; }
  QVariantList mlpActivations() const { return m_mlpActivations; }

  int residualLayer() const { return m_residualLayer; }
  QVariantList residualNorms() const { return m_residualNorms; }
  QVariantList residualLayersLast() const { return m_residualLayersLast; }

  QString device() const { return m_device; }
  bool done() const { return m_done; }
  QVariantMap meta() const { return m_meta; }

  QString lastError() const { return m_lastError; }

  QStringList logLines() const { return m_logLines; }
  QString lastJson() const { return m_lastJson; }
  double lastRoundTripMs() const { return m_lastRoundTripMs; }
  int lastPayloadBytes() const { return m_lastPayloadBytes; }

  Q_INVOKABLE void step(QString prompt, double temperature, int topK, double topP,
                        int vizLayer, int vizHead);
  Q_INVOKABLE void clearLog();

signals:
  void connectedChanged();
  void busyChanged();
  void generatedChanged();
  void tokensChanged();
  void topkChanged();
  void sampledChanged();
  void attentionChanged();
  void mlpChanged();
  void residualChanged();
  void residualLayersLastChanged();
  void metaChanged();
  void lastErrorChanged();
  void logLinesChanged();
  void lastJsonChanged();
  void perfChanged();

private slots:
  void onConnected();
  void onDisconnected();
  void onTextMessageReceived(const QString &message);
  void onErrorOccurred(QAbstractSocket::SocketError error);
  void tryReconnect();

private:
  void connectNow();
  void setLastError(const QString &err);
  void appendLog(const QString &line);
  static QVariant jsonToVariant(const QJsonValue &v);

  static constexpr int MAX_TOKENS_DISPLAY = 256;
  static constexpr int MAX_LOG_LINES = 500;
  static constexpr int MAX_JSON_CHARS = 200000;

  QWebSocket m_ws;
  QTimer m_reconnectTimer;
  int m_reconnectAttempt = 0;

  bool m_connected = false;
  bool m_busy = false;

  QString m_generated;
  QStringList m_tokens;

  QVariantList m_topk;
  int m_sampledId = -1;
  QString m_sampledToken;
  double m_sampledProb = 0.0;

  int m_attentionLayer = 0;
  int m_attentionHead = 0;
  QVariantList m_attentionMatrix;

  int m_mlpLayer = 0;
  QVariantList m_mlpActivations;

  int m_residualLayer = 0;
  QVariantList m_residualNorms;
  QVariantList m_residualLayersLast;

  QString m_device = "unknown";
  bool m_done = false;
  QVariantMap m_meta;

  QString m_lastError;

  QStringList m_logLines;
  QString m_lastJson;

  QElapsedTimer m_roundTripTimer;
  bool m_roundTripActive = false;
  double m_lastRoundTripMs = 0.0;
  int m_lastPayloadBytes = 0;
};
