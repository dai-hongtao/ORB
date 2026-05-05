#include "HeartbeatService.h"

#include <WiFi.h>

namespace orb {

void HeartbeatService::begin() {
  lastHeartbeatMs_ = 0;
  sequence_ = 0;
  stateRevision_ = 1;
  targetPort_ = kHeartbeatPort;
  configuredPort_ = false;
  Serial.printf("[Heartbeat] 已启用，UDP 端口=%u，周期=%lu ms\n",
                kHeartbeatPort,
                static_cast<unsigned long>(kHeartbeatIntervalMs));
}

void HeartbeatService::handle(const WiFiProvisioning& provisioning, const RegistryStore& registry) {
  if (WiFi.status() != WL_CONNECTED || provisioning.isAccessPointMode()) {
    return;
  }

  const uint32_t now = millis();
  if (now - lastHeartbeatMs_ < kHeartbeatIntervalMs) {
    return;
  }

  lastHeartbeatMs_ = now;
  ++sequence_;

  const String payload = buildPayload(provisioning, registry);
  const IPAddress target = broadcastAddress();

  udp_.beginPacket(target, targetPort_);
  udp_.write(reinterpret_cast<const uint8_t*>(payload.c_str()), payload.length());
  const bool ok = udp_.endPacket() == 1;

  if (!ok) {
    Serial.println("[Heartbeat] 广播失败");
    return;
  }

  if ((sequence_ % 10U) == 1U) {
    Serial.printf("[Heartbeat] 已广播：seq=%lu，revision=%lu，目标=%s:%u，来源=%s\n",
                  static_cast<unsigned long>(sequence_),
                  static_cast<unsigned long>(stateRevision_),
                  target.toString().c_str(),
                  targetPort_,
                  configuredPort_ ? "上位机配置" : "默认端口");
  }
}

void HeartbeatService::markStateChanged() {
  ++stateRevision_;
  Serial.printf("[Heartbeat] 状态修订已更新：revision=%lu\n", static_cast<unsigned long>(stateRevision_));
}

void HeartbeatService::configureTargetPort(uint16_t port) {
  if (port == 0) {
    return;
  }

  targetPort_ = port;
  configuredPort_ = true;
  Serial.printf("[Heartbeat] 已切换 UDP 目标端口：%u（默认=%u）\n", targetPort_, kHeartbeatPort);
}

uint32_t HeartbeatService::stateRevision() const {
  return stateRevision_;
}

uint32_t HeartbeatService::intervalMs() const {
  return kHeartbeatIntervalMs;
}

uint16_t HeartbeatService::defaultPort() const {
  return kHeartbeatPort;
}

uint16_t HeartbeatService::targetPort() const {
  return targetPort_;
}

bool HeartbeatService::configuredPort() const {
  return configuredPort_;
}

const char* HeartbeatService::delivery() const {
  return "udp_broadcast";
}

String HeartbeatService::buildPayload(const WiFiProvisioning& provisioning, const RegistryStore& registry) const {
  size_t registeredCount = 0;
  size_t presentCount = 0;
  for (const RegistryEntry& entry : registry.entries()) {
    if (entry.registered) {
      ++registeredCount;
    }
    if (entry.present) {
      ++presentCount;
    }
  }

  String json = "{";
  json += "\"type\":\"heartbeat\",";
  json += "\"protocol_version\":1,";
  json += "\"device_name\":\"" + provisioning.deviceName() + "\",";
  json += "\"firmware_version\":\"";
  json += kFirmwareVersion;
  json += "\",";
  json += "\"ip\":\"" + provisioning.currentIP() + "\",";
  json += "\"mac\":\"" + WiFi.macAddress() + "\",";
  json += "\"port\":";
  json += String(kWebPort);
  json += ",\"sequence\":";
  json += String(sequence_);
  json += ",\"state_revision\":";
  json += String(stateRevision_);
  json += ",\"heartbeat_interval_ms\":";
  json += String(kHeartbeatIntervalMs);
  json += ",\"default_port\":";
  json += String(kHeartbeatPort);
  json += ",\"target_port\":";
  json += String(targetPort_);
  json += ",\"configured_port\":";
  json += configuredPort_ ? "true" : "false";
  json += ",\"delivery\":\"";
  json += delivery();
  json += "\"";
  json += ",\"uptime_ms\":";
  json += String(millis());
  json += ",\"registered_count\":";
  json += String(registeredCount);
  json += ",\"present_count\":";
  json += String(presentCount);
  json += "}";
  return json;
}

IPAddress HeartbeatService::broadcastAddress() {
  const IPAddress ip = WiFi.localIP();
  const IPAddress mask = WiFi.subnetMask();
  IPAddress broadcast;

  for (uint8_t index = 0; index < 4; ++index) {
    broadcast[index] = static_cast<uint8_t>(ip[index] | ~mask[index]);
  }

  return broadcast;
}

}  // namespace orb
