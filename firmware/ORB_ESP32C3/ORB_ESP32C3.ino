#include <Arduino.h>
#include <WiFi.h>
#include <Wire.h>

#include "src/ApiServer.h"
#include "src/BonjourService.h"
#include "src/CalibrationStore.h"
#include "src/Config.h"
#include "src/HeartbeatService.h"
#include "src/MCP4728Driver.h"
#include "src/ModuleBus.h"
#include "src/RegistryStore.h"
#include "src/SmoothingEngine.h"
#include "src/WiFiProvisioning.h"

namespace {
orb::RegistryStore registryStore;
orb::CalibrationStore calibrationStore;
orb::MCP4728Driver dacDriver;
orb::ModuleBus moduleBus;
orb::SmoothingEngine smoothingEngine;
orb::WiFiProvisioning wifiProvisioning;
orb::BonjourService bonjourService;
orb::HeartbeatService heartbeatService;
orb::ApiServer apiServer(registryStore, calibrationStore, moduleBus, dacDriver, smoothingEngine, heartbeatService, wifiProvisioning);

wl_status_t lastWiFiStatus = WL_IDLE_STATUS;

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
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("ORB ESP32C3 正在启动...");

  Wire.begin(orb::kPinI2CSDA, orb::kPinI2CSCL, orb::kI2CFrequencyHz);

  registryStore.begin();
  calibrationStore.begin();
  dacDriver.begin(Wire);
  moduleBus.begin(Wire);
  smoothingEngine.begin(dacDriver);
  wifiProvisioning.begin();
  heartbeatService.begin();
  const bool shouldStartBonjour = !wifiProvisioning.isAccessPointMode() && WiFi.status() == WL_CONNECTED;
  const bool bonjourStarted =
      shouldStartBonjour ? bonjourService.begin(wifiProvisioning.deviceName(), orb::kWebPort) : false;
  if (!shouldStartBonjour) {
    Serial.println("[mDNS] 跳过 Bonjour：当前处于配网模式或尚未接入局域网");
  }
  apiServer.begin();

  moduleBus.refreshPresence(registryStore);
  lastWiFiStatus = WiFi.status();

  Serial.printf("设备名称：%s\n", wifiProvisioning.deviceName().c_str());
  Serial.printf("当前网络地址：http://%s/\n", wifiProvisioning.currentIP().c_str());
  Serial.printf("Bonjour 地址：http://%s.local/\n", wifiProvisioning.deviceName().c_str());
  Serial.printf("Bonjour 广播：%s\n", bonjourStarted ? "成功" : "失败");
  Serial.printf("当前 Wi-Fi 状态：%s (%d)\n", wifiStatusLabel(lastWiFiStatus), static_cast<int>(lastWiFiStatus));
}

void loop() {
  wifiProvisioning.handleDNS();
  if (wifiProvisioning.promoteStationConnectionIfNeeded()) {
    const bool bonjourRestarted = bonjourService.begin(wifiProvisioning.deviceName(), orb::kWebPort);
    Serial.printf("[mDNS] 切换到局域网后重新广播：%s\n", bonjourRestarted ? "成功" : "失败");
    Serial.printf("[HTTP] 当前可访问地址：http://%s/\n", wifiProvisioning.currentIP().c_str());
  }
  heartbeatService.handle(wifiProvisioning, registryStore);
  apiServer.handleClient();
  smoothingEngine.tick(registryStore);

  const wl_status_t currentStatus = WiFi.status();
  if (currentStatus != lastWiFiStatus) {
    lastWiFiStatus = currentStatus;
    Serial.printf("[WiFi] 站点状态变更：%s (%d)\n", wifiStatusLabel(currentStatus), static_cast<int>(currentStatus));
    if (currentStatus == WL_CONNECTED) {
      Serial.printf("[WiFi] 已连上路由器，IP=%s，MAC=%s\n",
                    WiFi.localIP().toString().c_str(),
                    WiFi.macAddress().c_str());
    }
  }
}
