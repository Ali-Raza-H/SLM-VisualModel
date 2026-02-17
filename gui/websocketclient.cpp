#include "websocketclient.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QUrl>
#include <QtMath>

static QString wsUrl() { return QStringLiteral("ws://localhost:8765"); }

WebSocketClient::WebSocketClient(QObject *parent) : QObject(parent) {
  connect(&m_ws, &QWebSocket::connected, this, &WebSocketClient::onConnected);
  connect(&m_ws, &QWebSocket::disconnected, this, &WebSocketClient::onDisconnected);
  connect(&m_ws, &QWebSocket::textMessageReceived, this, &WebSocketClient::onTextMessageReceived);
  connect(&m_ws, &QWebSocket::errorOccurred, this, &WebSocketClient::onErrorOccurred);

  m_reconnectTimer.setSingleShot(true);
  connect(&m_reconnectTimer, &QTimer::timeout, this, &WebSocketClient::tryReconnect);

  connectNow();
}

void WebSocketClient::connectNow() {
  setLastError(QString());
  if (m_reconnectAttempt > 0) {
    appendLog(QStringLiteral("Connecting to %1 (attempt %2)...").arg(wsUrl()).arg(m_reconnectAttempt));
  } else {
    appendLog(QStringLiteral("Connecting to %1...").arg(wsUrl()));
  }
  m_ws.open(QUrl(wsUrl()));
}

void WebSocketClient::tryReconnect() { connectNow(); }

void WebSocketClient::onConnected() {
  m_connected = true;
  m_reconnectAttempt = 0;
  emit connectedChanged();
  setLastError(QString());
  appendLog(QStringLiteral("CONNECTED"));
}

void WebSocketClient::onDisconnected() {
  m_connected = false;
  emit connectedChanged();

  if (m_busy) {
    m_busy = false;
    emit busyChanged();
  }

  // Exponential backoff up to 5 seconds.
  const int baseMs = 250;
  const int maxMs = 5000;
  const int shift = qMin(m_reconnectAttempt, 5);
  const int delay = qMin(maxMs, baseMs * (1 << shift));
  m_reconnectAttempt++;
  m_reconnectTimer.start(delay);
  appendLog(QStringLiteral("DISCONNECTED (reconnect in %1ms)").arg(delay));
}

void WebSocketClient::onErrorOccurred(QAbstractSocket::SocketError error) {
  Q_UNUSED(error);
  setLastError(m_ws.errorString());
  appendLog(QStringLiteral("SOCKET ERROR: %1").arg(m_ws.errorString()));
}

void WebSocketClient::setLastError(const QString &err) {
  if (m_lastError == err)
    return;
  m_lastError = err;
  emit lastErrorChanged();
}

void WebSocketClient::appendLog(const QString &line) {
  const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss.zzz"));
  m_logLines.append(QStringLiteral("[%1] %2").arg(stamp, line));
  if (m_logLines.size() > MAX_LOG_LINES) {
    m_logLines = m_logLines.mid(m_logLines.size() - MAX_LOG_LINES);
  }
  emit logLinesChanged();
}

void WebSocketClient::clearLog() {
  if (m_logLines.isEmpty())
    return;
  m_logLines.clear();
  emit logLinesChanged();
}

QVariant WebSocketClient::jsonToVariant(const QJsonValue &v) {
  if (v.isBool())
    return v.toBool();
  if (v.isDouble())
    return v.toDouble();
  if (v.isString())
    return v.toString();
  if (v.isNull() || v.isUndefined())
    return QVariant();

  if (v.isArray()) {
    QVariantList list;
    const auto arr = v.toArray();
    list.reserve(arr.size());
    for (const auto &item : arr) {
      list.append(jsonToVariant(item));
    }
    return list;
  }

  if (v.isObject()) {
    QVariantMap map;
    const auto obj = v.toObject();
    for (auto it = obj.begin(); it != obj.end(); ++it) {
      map.insert(it.key(), jsonToVariant(it.value()));
    }
    return map;
  }

  return QVariant();
}

void WebSocketClient::onTextMessageReceived(const QString &message) {
  // Store raw payload for visibility/debugging, but cap size to avoid memory spikes.
  QString clipped = message;
  if (clipped.size() > MAX_JSON_CHARS) {
    clipped = clipped.left(MAX_JSON_CHARS);
    clipped.append(QStringLiteral("\n...(truncated)..."));
  }
  if (m_lastJson != clipped) {
    m_lastJson = clipped;
    emit lastJsonChanged();
  }

  const int payloadBytes = message.toUtf8().size();
  bool perfDirty = false;
  if (m_lastPayloadBytes != payloadBytes) {
    m_lastPayloadBytes = payloadBytes;
    perfDirty = true;
  }

  if (m_roundTripActive) {
    m_roundTripActive = false;
    const qint64 ms = m_roundTripTimer.elapsed();
    const double rtt = (ms < 0) ? 0.0 : double(ms);
    if (m_lastRoundTripMs != rtt) {
      m_lastRoundTripMs = rtt;
      perfDirty = true;
    }
  }
  if (perfDirty) {
    emit perfChanged();
  }

  if (m_busy) {
    m_busy = false;
    emit busyChanged();
  }

  QJsonParseError parseError;
  const auto doc = QJsonDocument::fromJson(message.toUtf8(), &parseError);
  if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
    setLastError(QStringLiteral("JSON parse error: %1").arg(parseError.errorString()));
    appendLog(QStringLiteral("RECV INVALID JSON (%1 bytes): %2").arg(payloadBytes).arg(parseError.errorString()));
    return;
  }

  const auto root = doc.object();
  if (root.contains("error")) {
    setLastError(root.value("error").toString());
    appendLog(QStringLiteral("BACKEND ERROR: %1").arg(m_lastError));
    return;
  }

  setLastError(QString());

  // tokens
  if (root.contains("tokens") && root.value("tokens").isArray()) {
    const auto arr = root.value("tokens").toArray();
    const int n = arr.size();
    const int start = (n > MAX_TOKENS_DISPLAY) ? (n - MAX_TOKENS_DISPLAY) : 0;
    QStringList out;
    out.reserve(n - start);
    for (int i = start; i < n; i++) {
      out.append(arr.at(i).toString());
    }
    m_tokens = out;
    emit tokensChanged();
  }

  // generated
  if (root.contains("generated")) {
    m_generated = root.value("generated").toString();
    emit generatedChanged();
  }

  // sampled
  if (root.contains("sampled") && root.value("sampled").isObject()) {
    const auto s = root.value("sampled").toObject();
    m_sampledId = s.value("id").toInt(-1);
    m_sampledToken = s.value("token").toString();
    m_sampledProb = s.value("prob").toDouble(0.0);
    emit sampledChanged();
  }

  // topk
  if (root.contains("topk") && root.value("topk").isArray()) {
    const auto arr = root.value("topk").toArray();
    QVariantList list;
    list.reserve(arr.size());
    for (const auto &v : arr) {
      list.append(jsonToVariant(v));
    }
    m_topk = list;
    emit topkChanged();
  }

  // attention
  if (root.contains("attention") && root.value("attention").isObject()) {
    const auto a = root.value("attention").toObject();
    m_attentionLayer = a.value("layer").toInt(m_attentionLayer);
    m_attentionHead = a.value("head").toInt(m_attentionHead);
    if (a.contains("matrix")) {
      m_attentionMatrix = jsonToVariant(a.value("matrix")).toList();
    }
    emit attentionChanged();
  }

  // mlp
  if (root.contains("mlp") && root.value("mlp").isObject()) {
    const auto m = root.value("mlp").toObject();
    m_mlpLayer = m.value("layer").toInt(m_mlpLayer);
    if (m.contains("activations")) {
      m_mlpActivations = jsonToVariant(m.value("activations")).toList();
    }
    emit mlpChanged();
  }

  // residual
  if (root.contains("residual") && root.value("residual").isObject()) {
    const auto r = root.value("residual").toObject();
    m_residualLayer = r.value("layer").toInt(m_residualLayer);
    if (r.contains("norms")) {
      m_residualNorms = jsonToVariant(r.value("norms")).toList();
    }
    emit residualChanged();
  }

  // residual_layers_last
  if (root.contains("residual_layers_last")) {
    m_residualLayersLast = jsonToVariant(root.value("residual_layers_last")).toList();
    emit residualLayersLastChanged();
  }

  // meta
  if (root.contains("meta") && root.value("meta").isObject()) {
    const auto meta = root.value("meta").toObject();

    m_meta = jsonToVariant(QJsonValue(meta)).toMap();
    m_device = meta.value("device").toString(m_device);
    m_done = meta.value("done").toBool(false);
    emit metaChanged();
  }

  appendLog(QStringLiteral("RECV %1 bytes  rtt=%2ms  done=%3")
                .arg(payloadBytes)
                .arg(QString::number(m_lastRoundTripMs, 'f', 0))
                .arg(m_done ? QStringLiteral("true") : QStringLiteral("false")));
}

void WebSocketClient::step(QString prompt, double temperature, int topK, double topP, int vizLayer,
                           int vizHead) {
  if (!m_connected) {
    setLastError(QStringLiteral("Not connected to backend (%1).").arg(wsUrl()));
    appendLog(QStringLiteral("STEP blocked (not connected)"));
    return;
  }

  const bool willReset = !prompt.isEmpty();
  appendLog(QStringLiteral("STEP reset=%1 temp=%2 topk=%3 topp=%4 layer=%5 head=%6")
                .arg(willReset ? QStringLiteral("yes") : QStringLiteral("no"))
                .arg(QString::number(temperature, 'f', 2))
                .arg(topK)
                .arg(QString::number(topP, 'f', 2))
                .arg(vizLayer)
                .arg(vizHead));

  QJsonObject obj;
  obj.insert("prompt", prompt);
  obj.insert("temperature", temperature);
  obj.insert("top_k", topK);
  obj.insert("top_p", topP);
  obj.insert("step", true);
  obj.insert("viz_layer", vizLayer);
  obj.insert("viz_head", vizHead);

  const auto doc = QJsonDocument(obj);
  const auto payload = doc.toJson(QJsonDocument::Compact);
  m_ws.sendTextMessage(QString::fromUtf8(payload));
  m_roundTripTimer.restart();
  m_roundTripActive = true;

  if (!m_busy) {
    m_busy = true;
    emit busyChanged();
  }
}
