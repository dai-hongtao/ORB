#include "WiFiProvisioning.h"

namespace orb {

namespace {
const IPAddress kAccessPointIP(192, 168, 4, 1);
const IPAddress kAccessPointGateway(192, 168, 4, 1);
const IPAddress kAccessPointMask(255, 255, 255, 0);
constexpr uint32_t kScanCacheMs = 10000;

const char* wifiModeLabel(wifi_mode_t mode) {
  switch (mode) {
    case WIFI_MODE_NULL:
      return "OFF";
    case WIFI_MODE_STA:
      return "STA";
    case WIFI_MODE_AP:
      return "AP";
    case WIFI_MODE_APSTA:
      return "AP+STA";
    default:
      return "未知";
  }
}

const char* wifiStatusLabel(wl_status_t status) {
  switch (status) {
    case WL_NO_SHIELD:
      return "无 Wi-Fi 模块";
    case WL_IDLE_STATUS:
      return "空闲";
    case WL_NO_SSID_AVAIL:
      return "找不到 SSID";
    case WL_SCAN_COMPLETED:
      return "扫描完成";
    case WL_CONNECTED:
      return "已连接";
    case WL_CONNECT_FAILED:
      return "连接失败";
    case WL_CONNECTION_LOST:
      return "连接丢失";
    case WL_DISCONNECTED:
      return "已断开";
    default:
      return "未知状态";
  }
}

String escapeHtml(const String& input) {
  String output;
  output.reserve(input.length() + 16);
  for (size_t i = 0; i < input.length(); ++i) {
    switch (input[i]) {
      case '&':
        output += F("&amp;");
        break;
      case '<':
        output += F("&lt;");
        break;
      case '>':
        output += F("&gt;");
        break;
      case '"':
        output += F("&quot;");
        break;
      case '\'':
        output += F("&#39;");
        break;
      default:
        output += input[i];
        break;
    }
  }
  return output;
}

String escapeJson(const String& input) {
  String output;
  output.reserve(input.length() + 16);
  for (size_t i = 0; i < input.length(); ++i) {
    const char c = input[i];
    switch (c) {
      case '\\':
        output += F("\\\\");
        break;
      case '"':
        output += F("\\\"");
        break;
      case '\b':
        output += F("\\b");
        break;
      case '\f':
        output += F("\\f");
        break;
      case '\n':
        output += F("\\n");
        break;
      case '\r':
        output += F("\\r");
        break;
      case '\t':
        output += F("\\t");
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          output += ' ';
        } else {
          output += c;
        }
        break;
    }
  }
  return output;
}
}

void WiFiProvisioning::begin() {
  Serial.println("[WiFi] 初始化配网管理");
  preferences_.begin(kWiFiNamespace, false);
  cachedScanJson_ = F("{\"ok\":true,\"networks\":[]}");
  if (!connectSavedStation()) {
    if (!startAccessPoint()) {
      Serial.println("[WiFi] 致命：配网热点启动失败，当前无法进入配网模式");
    }
  }
}

void WiFiProvisioning::attachRoutes(WebServer& server) {
  server.on("/", HTTP_GET, [this, &server]() {
    Serial.println("[WiFi] 打开配网页面");
    server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
    String html = buildProvisioningPage();
    server.send(200, "text/html; charset=utf-8", html);
  });

  server.on("/wifi/scan", HTTP_GET, [this, &server]() {
    Serial.println("[WiFi] 收到 Wi-Fi 扫描请求");
    server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
    server.send(200, "application/json; charset=utf-8", scanNetworksJson());
  });

  server.on("/wifi/save", HTTP_POST, [this, &server]() {
    String ssid = server.arg("ssid");
    ssid.trim();
    if (ssid.isEmpty() && server.hasArg("ssid_select")) {
      ssid = server.arg("ssid_select");
      ssid.trim();
    }
    const String password = server.arg("password");
    if (ssid.isEmpty()) {
      Serial.println("[WiFi] 保存凭据失败：SSID 为空");
      server.send(400, "text/plain; charset=utf-8", "SSID 不能为空。");
      return;
    }

    Serial.printf("[WiFi] 保存新的 Wi-Fi 凭据，SSID=%s\n", ssid.c_str());
    saveCredentials(ssid, password);
    server.sendHeader("Connection", "close");
    String html;
    html += F("<!doctype html><html><head><meta charset='utf-8'>");
    html += F("<meta name='viewport' content='width=device-width,initial-scale=1'>");
    html += F("<title>ORB 正在重启</title></head><body style='font-family:system-ui;padding:24px;'>");
    html += F("<h1>Wi-Fi 已保存</h1><p>SSID：<strong>");
    html += escapeHtml(ssid);
    html += F("</strong></p><p>ORB 即将重启，并尝试连接这个网络。</p>");
    html += F("</body></html>");
    server.send(200, "text/html; charset=utf-8", html);
    delay(750);
    ESP.restart();
  });

  server.on("/wifi/forget", HTTP_POST, [this, &server]() {
    Serial.println("[WiFi] 清除已保存的 Wi-Fi 凭据");
    clearCredentials();
    server.sendHeader("Connection", "close");
    server.send(
        200,
        "text/html; charset=utf-8",
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>ORB 正在重启</title></head><body style='font-family:system-ui;padding:24px;'>"
        "<h1>已清除 Wi-Fi</h1><p>已保存的网络凭据已经删除。ORB 将重启并回到配网模式。</p>"
        "</body></html>");
    delay(750);
    ESP.restart();
  });

  server.on("/generate_204", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/gen_204", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/hotspot-detect.html", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/connecttest.txt", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/ncsi.txt", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/success.txt", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/redirect", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
  server.on("/fwlink", HTTP_ANY, [this, &server]() { sendCaptivePortalRedirect(server); });
}

void WiFiProvisioning::handleDNS() {
  if (accessPointMode_) {
    dnsServer_.processNextRequest();
  }
}

bool WiFiProvisioning::handleCaptivePortalRequest(WebServer& server) {
  if (!accessPointMode_) {
    return false;
  }
  sendCaptivePortalRedirect(server);
  return true;
}

bool WiFiProvisioning::promoteStationConnectionIfNeeded() {
  if (!accessPointMode_ || WiFi.status() != WL_CONNECTED) {
    return false;
  }

  accessPointMode_ = false;
  dnsServer_.stop();
  WiFi.softAPdisconnect(true);
  Serial.printf("[WiFi] 检测到设备已接入路由器，关闭配网热点，当前 IP=%s\n",
                WiFi.localIP().toString().c_str());
  return true;
}

bool WiFiProvisioning::isAccessPointMode() const {
  return accessPointMode_;
}

String WiFiProvisioning::currentIP() const {
  return accessPointMode_ ? kAccessPointIP.toString() : WiFi.localIP().toString();
}

String WiFiProvisioning::deviceName() const {
  return deviceName_;
}

bool WiFiProvisioning::connectSavedStation() {
  String ssid;
  String password;
  if (!loadCredentials(ssid, password)) {
    Serial.println("[WiFi] 没有已保存的 Wi-Fi 凭据，进入配网模式");
    return false;
  }

  Serial.printf("[WiFi] 尝试连接已保存网络：%s\n", ssid.c_str());
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());

  const uint32_t startMs = millis();
  while (WiFi.status() != WL_CONNECTED &&
         millis() - startMs < kWiFiConnectTimeoutMs) {
    delay(250);
  }

  accessPointMode_ = WiFi.status() != WL_CONNECTED;
  Serial.printf("[WiFi] 连接结果：%s (%d)\n",
                wifiStatusLabel(WiFi.status()),
                static_cast<int>(WiFi.status()));
  if (!accessPointMode_) {
    Serial.printf("[WiFi] 已连接路由器，IP=%s，MAC=%s\n",
                  WiFi.localIP().toString().c_str(),
                  WiFi.macAddress().c_str());
  }
  return !accessPointMode_;
}

bool WiFiProvisioning::loadCredentials(String& ssid, String& password) {
  ssid = preferences_.getString("ssid", "");
  password = preferences_.getString("password", "");
  return !ssid.isEmpty();
}

void WiFiProvisioning::saveCredentials(const String& ssid, const String& password) {
  preferences_.putString("ssid", ssid);
  preferences_.putString("password", password);
}

void WiFiProvisioning::clearCredentials() {
  preferences_.remove("ssid");
  preferences_.remove("password");
}

bool WiFiProvisioning::startAccessPoint() {
  Serial.printf("[WiFi] 准备启动配网热点：SSID=%s，目标 IP=%s\n",
                kAccessPointSSID,
                kAccessPointIP.toString().c_str());

  accessPointMode_ = false;

  for (uint8_t attempt = 1; attempt <= 2; ++attempt) {
    if (attempt > 1) {
      Serial.println("[WiFi] 首次启动配网热点失败，准备重试");
    }

    WiFi.mode(WIFI_OFF);
    delay(100);
    WiFi.mode(WIFI_AP_STA);
    delay(150);

    const bool configOk = WiFi.softAPConfig(kAccessPointIP, kAccessPointGateway, kAccessPointMask);
    const bool apOk = WiFi.softAP(kAccessPointSSID, nullptr, kAccessPointChannel, false, 4);
    delay(150);

    const IPAddress softApIP = WiFi.softAPIP();
    const wifi_mode_t mode = WiFi.getMode();

    Serial.printf("[WiFi] 配网热点启动尝试 %u：softAPConfig=%s，softAP=%s，模式=%s，AP IP=%s\n",
                  attempt,
                  configOk ? "成功" : "失败",
                  apOk ? "成功" : "失败",
                  wifiModeLabel(mode),
                  softApIP.toString().c_str());

    if (configOk && apOk && softApIP != IPAddress((uint32_t)0)) {
      dnsServer_.stop();
      dnsServer_.start(53, "*", kAccessPointIP);
      accessPointMode_ = true;
      Serial.printf("[WiFi] 已启动配网热点：%s，频道=%u，隐藏=%s\n",
                    WiFi.softAPSSID().c_str(),
                    static_cast<unsigned>(kAccessPointChannel),
                    "否");
      Serial.printf("[WiFi] 配网页面地址：http://%s/\n", kAccessPointIP.toString().c_str());
      return true;
    }
  }

  Serial.printf("[WiFi] 配网热点启动失败：模式=%s，AP IP=%s\n",
                wifiModeLabel(WiFi.getMode()),
                WiFi.softAPIP().toString().c_str());
  return false;
}

String WiFiProvisioning::buildProvisioningPage() const {
  String html =
      F("<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>ORB 配网</title>"
        "<style>"
        ":root{color-scheme:light;font-family:system-ui,sans-serif;}"
        "body{margin:0;background:#f5f7fb;color:#162033;}"
        "main{max-width:560px;margin:0 auto;padding:24px;}"
        ".card{background:#fff;border-radius:18px;padding:24px;box-shadow:0 18px 40px rgba(0,0,0,.08);}"
        "h1{margin:0 0 8px;font-size:28px;}"
        "p{line-height:1.5;margin:0 0 12px;}"
        ".muted{color:#5b6475;font-size:14px;}"
        "label{display:block;margin:16px 0 8px;font-weight:600;}"
        "input,select,button{width:100%;box-sizing:border-box;border-radius:12px;font:inherit;}"
        "input,select{padding:14px 16px;border:1px solid #cfd6e4;background:#fff;}"
        ".scan-row{display:flex;gap:10px;align-items:center;}"
        ".scan-row select{flex:1;}"
        ".scan-row button{width:auto;white-space:nowrap;padding:14px 16px;border:none;background:#162033;color:#fff;}"
        ".primary{margin-top:20px;padding:14px 16px;border:none;background:#1b6ef3;color:#fff;font-weight:700;}"
        ".secondary{margin-top:14px;padding:12px 16px;border:1px solid #d8deea;background:#fff;color:#162033;}"
        "#scan-status{margin-top:10px;font-size:13px;color:#5b6475;min-height:20px;}"
        "</style></head><body><main><section class='card'>"
        "<h1>ORB 配网</h1>"
        "<p>请把 ORB 接入你的本地 Wi-Fi。手机或电脑连接到配网热点后，通常会自动弹出这个页面。</p>"
        "<p class='muted'>设备：<strong>__DEVICE__</strong><br>备用地址：<strong>http://192.168.4.1/</strong></p>"
        "<form method='POST' action='/wifi/save' autocomplete='off'>"
        "<label for='ssid_select'>附近的网络</label>"
        "<div class='scan-row'>"
        "<select id='ssid_select' name='ssid_select'><option value=''>正在扫描附近 Wi-Fi...</option></select>"
        "<button id='refresh_btn' type='button'>刷新列表</button>"
        "</div>"
        "<div id='scan-status'>正在扫描附近 Wi-Fi...</div>"
        "<label for='ssid'>SSID</label>"
        "<input id='ssid' name='ssid' placeholder='可从下拉列表中选择，也可以手动输入' required>"
        "<label for='password'>密码</label>"
        "<input id='password' name='password' type='password' placeholder='请输入 Wi-Fi 密码'>"
        "<button class='primary' type='submit'>保存 Wi-Fi</button>"
        "</form>"
        "<form method='POST' action='/wifi/forget'>"
        "<button class='secondary' type='submit'>清除已保存的 Wi-Fi</button>"
        "</form>"
        "</section></main>"
        "<script>"
        "const selectEl=document.getElementById('ssid_select');"
        "const ssidInput=document.getElementById('ssid');"
        "const statusEl=document.getElementById('scan-status');"
        "const refreshBtn=document.getElementById('refresh_btn');"
        "async function loadNetworks(){"
        "statusEl.textContent='正在扫描附近 Wi-Fi...';"
        "selectEl.innerHTML='<option value=\"\">正在扫描附近 Wi-Fi...</option>';"
        "refreshBtn.disabled=true;"
        "try{"
        "const response=await fetch('/wifi/scan',{cache:'no-store'});"
        "const data=await response.json();"
        "selectEl.innerHTML='<option value=\"\">请选择一个扫描到的网络</option>';"
        "if(!data.ok||!Array.isArray(data.networks)||!data.networks.length){"
        "statusEl.textContent='没有扫描到附近的 Wi-Fi，你仍然可以手动输入 SSID。';"
        "return;"
        "}"
        "for(const network of data.networks){"
        "const option=document.createElement('option');"
        "option.value=network.ssid;"
        "option.textContent=network.ssid + ' (' + network.rssi + ' dBm' + (network.secure ? '，已加密' : '，开放网络') + ')';"
        "selectEl.appendChild(option);"
        "}"
        "statusEl.textContent='你可以从列表中选择网络，也可以手动输入 SSID。';"
        "}catch(error){"
        "selectEl.innerHTML='<option value=\"\">扫描失败</option>';"
        "statusEl.textContent='扫描失败，你仍然可以手动输入 SSID。';"
        "}finally{refreshBtn.disabled=false;}"
        "}"
        "selectEl.addEventListener('change',()=>{if(selectEl.value){ssidInput.value=selectEl.value;ssidInput.focus();}});"
        "refreshBtn.addEventListener('click',loadNetworks);"
        "loadNetworks();"
        "</script></body></html>");

  html.replace("__DEVICE__", escapeHtml(deviceName_));
  return html;
}

String WiFiProvisioning::scanNetworksJson() {
  if (!accessPointMode_) {
    return F("{\"ok\":false,\"error\":\"not_in_ap_mode\",\"networks\":[]}");
  }

  const uint32_t now = millis();
  if (lastScanMs_ != 0 && !cachedScanJson_.isEmpty() && now - lastScanMs_ < kScanCacheMs) {
    Serial.printf("[WiFi] 使用缓存的扫描结果，距上次扫描 %lu ms\n", now - lastScanMs_);
    return cachedScanJson_;
  }

  const int networkCount = WiFi.scanNetworks();
  String json;
  if (networkCount < 0) {
    Serial.println("[WiFi] 扫描附近 Wi-Fi 失败");
    cachedScanJson_ = F("{\"ok\":false,\"error\":\"scan_failed\",\"networks\":[]}");
    lastScanMs_ = now;
    return cachedScanJson_;
  }

  Serial.printf("[WiFi] 扫描完成，共发现 %d 个网络\n", networkCount);

  json = F("{\"ok\":true,\"networks\":[");
  bool first = true;
  for (int i = 0; i < networkCount; ++i) {
    const String ssid = WiFi.SSID(i);
    if (ssid.isEmpty()) {
      continue;
    }

    bool duplicate = false;
    for (int previousIndex = 0; previousIndex < i; ++previousIndex) {
      if (WiFi.SSID(previousIndex) == ssid) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) {
      continue;
    }

    if (!first) {
      json += ",";
    }
    first = false;

    json += "{\"ssid\":\"";
    json += escapeJson(ssid);
    json += "\",\"rssi\":";
    json += String(WiFi.RSSI(i));
    json += ",\"secure\":";
    json += WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "false" : "true";
    json += "}";
  }
  json += "]}";

  WiFi.scanDelete();
  cachedScanJson_ = json;
  lastScanMs_ = now;
  return cachedScanJson_;
}

void WiFiProvisioning::sendCaptivePortalRedirect(WebServer& server) {
  server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  server.sendHeader("Location", String("http://") + kAccessPointIP.toString() + "/", true);
  server.send(302, "text/plain", "");
}

}  // namespace orb
