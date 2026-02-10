#include "websocketclient.h"

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
  m_ws.open(QUrl(wsUrl()));
}

void WebSocketClient::tryReconnect() { connectNow(); }

void WebSocketClient::onConnected() {
  m_connected = true;
  m_reconnectAttempt = 0;
  emit connectedChanged();
  setLastError(QString());
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
}

void WebSocketClient::onErrorOccurred(QAbstractSocket::SocketError error) {
  Q_UNUSED(error);
  setLastError(m_ws.errorString());
}

void WebSocketClient::setLastError(const QString &err) {
  if (m_lastError == err)
    return;
  m_lastError = err;
  emit lastErrorChanged();
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
  if (m_busy) {
    m_busy = false;
    emit busyChanged();
  }

  QJsonParseError parseError;
  const auto doc = QJsonDocument::fromJson(message.toUtf8(), &parseError);
  if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
    setLastError(QStringLiteral("JSON parse error: %1").arg(parseError.errorString()));
    return;
  }

  const auto root = doc.object();
  if (root.contains("error")) {
    setLastError(root.value("error").toString());
    return;
  }

  setLastError(QString());

  // tokens
  if (root.contains("tokens") && root.value("tokens").isArray()) {
    const auto arr = root.value("tokens").toArray();
    QStringList out;
    out.reserve(arr.size());
    for (const auto &v : arr) {
      out.append(v.toString());
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
    m_device = meta.value("device").toString(m_device);
    m_done = meta.value("done").toBool(false);
    emit metaChanged();
  }
}

void WebSocketClient::step(QString prompt, double temperature, int topK, double topP, int vizLayer,
                           int vizHead) {
  if (!m_connected) {
    setLastError(QStringLiteral("Not connected to backend (%1).").arg(wsUrl()));
    return;
  }

  QJsonObject obj;
  obj.insert("prompt", prompt);
  obj.insert("temperature", temperature);
  obj.insert("top_k", topK);
  obj.insert("top_p", topP);
  obj.insert("step", true);
  obj.insert("viz_layer", vizLayer);
  obj.insert("viz_head", vizHead);

  const auto doc = QJsonDocument(obj);
  m_ws.sendTextMessage(QString::fromUtf8(doc.toJson(QJsonDocument::Compact)));

  if (!m_busy) {
    m_busy = true;
    emit busyChanged();
  }
}

