#include "ApiServer.h"

#include <Update.h>

namespace orb {

ApiServer::ApiServer(
    RegistryStore& registry,
    CalibrationStore& calibrationStore,
    ModuleBus& moduleBus,
    MCP4728Driver& dacDriver,
    SmoothingEngine& smoothing,
    HeartbeatService& heartbeat,
    WiFiProvisioning& provisioning)
    : registry_(registry),
      calibrationStore_(calibrationStore),
      moduleBus_(moduleBus),
      dacDriver_(dacDriver),
      smoothing_(smoothing),
      heartbeat_(heartbeat),
      provisioning_(provisioning),
      server_(kWebPort) {}

void ApiServer::begin() {
  provisioning_.attachRoutes(server_);

  server_.on("/api/v1/ping", HTTP_GET, [this]() { handlePing(); });
  server_.on("/api/v1/heartbeat/config", HTTP_POST, [this]() { handleHeartbeatConfig(); });
  server_.on("/api/v1/state", HTTP_GET, [this]() { handleState(); });
  server_.on("/api/v1/smoothing", HTTP_POST, [this]() { handleSmoothing(); });
  server_.on("/api/v1/frame", HTTP_POST, [this]() { handleFrame(); });
  server_.on("/api/v1/outputs", HTTP_POST, [this]() { handleOutputs(); });
  server_.on("/api/v1/preview", HTTP_POST, [this]() { handlePreview(); });
  server_.on("/api/v1/modules/register", HTTP_POST, [this]() { handleRegister(); });
  server_.on("/api/v1/modules/delete", HTTP_POST, [this]() { handleDelete(); });
  server_.on("/api/v1/modules/reset", HTTP_POST, [this]() { handleReset(); });
  server_.on("/api/v1/i2c/write_address", HTTP_POST, [this]() { handleI2CWriteAddress(); });
  server_.on("/api/v1/calibration/save", HTTP_POST, [this]() { handleCalibrationSave(); });
  server_.on(
      "/api/v1/firmware/upload",
      HTTP_POST,
      [this]() { finalizeFirmwareUpload(); },
      [this]() { handleFirmwareUpload(); });
  server_.onNotFound([this]() {
    if (provisioning_.handleCaptivePortalRequest(server_)) {
      return;
    }
    server_.send(404, "application/json", "{\"ok\":false}");
  });

  server_.begin();
  Serial.printf("[HTTP] Web 服务器已启动，监听端口 %u\n", kWebPort);
}

void ApiServer::handleClient() {
  server_.handleClient();
}

void ApiServer::handlePing() {
  String json = "{";
  json += "\"ok\":true,";
  json += "\"device_name\":\"" + provisioning_.deviceName() + "\",";
  json += "\"firmware_version\":\"";
  json += kFirmwareVersion;
  json += "\",";
  json += "\"ip\":\"" + provisioning_.currentIP() + "\",";
  json += "\"mac\":\"" + WiFi.macAddress() + "\",";
  json += "\"port\":";
  json += String(kWebPort);
  json += ",";
  json += "\"state_revision\":";
  json += String(heartbeat_.stateRevision());
  json += ",";
  json += "\"heartbeat_interval_ms\":";
  json += String(heartbeat_.intervalMs());
  json += ",";
  json += "\"heartbeat_default_port\":";
  json += String(heartbeat_.defaultPort());
  json += ",";
  json += "\"heartbeat_target_port\":";
  json += String(heartbeat_.targetPort());
  json += ",";
  json += "\"heartbeat_configured_port\":";
  json += heartbeat_.configuredPort() ? "true" : "false";
  json += ",";
  json += "\"heartbeat_delivery\":\"";
  json += heartbeat_.delivery();
  json += "\"";
  json += "}";
  server_.send(200, "application/json", json);
}

void ApiServer::handleHeartbeatConfig() {
  if (!server_.hasArg("udp_port")) {
    Serial.println("[HTTP] 心跳配置失败：缺少 udp_port");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_udp_port\"}");
    return;
  }

  const uint16_t udpPort = static_cast<uint16_t>(server_.arg("udp_port").toInt());
  if (udpPort == 0) {
    Serial.println("[HTTP] 心跳配置失败：udp_port 非法");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_udp_port\"}");
    return;
  }

  heartbeat_.configureTargetPort(udpPort);
  Serial.printf("[HTTP] 已确认心跳配置：UDP 目标端口=%u\n", udpPort);

  String json = "{\"ok\":true,\"heartbeat_default_port\":";
  json += String(heartbeat_.defaultPort());
  json += ",\"heartbeat_target_port\":";
  json += String(heartbeat_.targetPort());
  json += ",\"heartbeat_configured_port\":";
  json += heartbeat_.configuredPort() ? "true" : "false";
  json += ",\"heartbeat_delivery\":\"";
  json += heartbeat_.delivery();
  json += "\"}";
  server_.send(200, "application/json", json);
}

void ApiServer::handleState() {
  moduleBus_.refreshPresence(registry_);
  Serial.printf("[HTTP] 返回状态：IP=%s，MAC=%s，模式=%s\n",
                provisioning_.currentIP().c_str(),
                WiFi.macAddress().c_str(),
                provisioning_.isAccessPointMode() ? "AP" : "STA");
  server_.send(200, "application/json", buildStateJson());
}

void ApiServer::handleSmoothing() {
  const ModuleType type =
      server_.hasArg("module_type") ? static_cast<ModuleType>(server_.arg("module_type").toInt()) : ModuleType::Balance;
  const SmoothingConfig current = smoothing_.configFor(type);
  SmoothingConfig config = current;
  config.settleTimeMs = server_.hasArg("settle_time_ms")
                            ? static_cast<uint16_t>(server_.arg("settle_time_ms").toInt())
                            : current.settleTimeMs;
  config.aMax = server_.hasArg("a_max") ? server_.arg("a_max").toFloat() : current.aMax;
  config.vMax = server_.hasArg("v_max") ? server_.arg("v_max").toFloat() : current.vMax;
  config.jitterFrequencyHz =
      server_.hasArg("jitter_frequency_hz") ? server_.arg("jitter_frequency_hz").toFloat() : current.jitterFrequencyHz;
  config.jitterAmplitude =
      server_.hasArg("jitter_amplitude") ? server_.arg("jitter_amplitude").toFloat() : current.jitterAmplitude;
  config.jitterDispersion =
      server_.hasArg("jitter_dispersion") ? server_.arg("jitter_dispersion").toFloat() : current.jitterDispersion;

  smoothing_.setConfig(type, config);
  const SmoothingConfig applied = smoothing_.configFor(type);
  heartbeat_.markStateChanged();
  Serial.printf("[HTTP] 更新运动参数：类型=%s，到位时间=%u ms，a_max=%.2f，v_max=%.2f，抖动频率=%.2f Hz，抖动振幅=%.2f%%FS，离散程度=%.2f\n",
                moduleTypeName(type),
                static_cast<unsigned>(applied.settleTimeMs),
                applied.aMax,
                applied.vMax,
                applied.jitterFrequencyHz,
                applied.jitterAmplitude,
                applied.jitterDispersion);
  server_.send(200, "application/json", buildStateJson());
}

void ApiServer::handleFrame() {
  if (!server_.hasArg("frame_id") || !server_.hasArg("channels")) {
    Serial.println("[HTTP] 输出帧失败：缺少 frame_id 或 channels");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_frame_fields\"}");
    return;
  }

  const long frameId = server_.arg("frame_id").toInt();
  const String channelsArg = server_.arg("channels");

  size_t appliedCount = 0;
  uint8_t firstModuleId = 0;
  uint8_t firstChannelIndex = 0;
  uint16_t firstTargetCode = 0;

  int start = 0;
  while (start <= channelsArg.length()) {
    int end = channelsArg.indexOf(';', start);
    if (end < 0) {
      end = channelsArg.length();
    }

    String token = channelsArg.substring(start, end);
    token.trim();
    if (!token.isEmpty()) {
      const int firstComma = token.indexOf(',');
      const int secondComma = token.indexOf(',', firstComma + 1);
      if (firstComma <= 0 || secondComma <= firstComma + 1) {
        Serial.printf("[HTTP] 输出帧失败：非法通道条目 %s\n", token.c_str());
        server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_frame_entry\"}");
        return;
      }

      const uint8_t moduleId = static_cast<uint8_t>(token.substring(0, firstComma).toInt());
      const uint8_t channelIndex = static_cast<uint8_t>(token.substring(firstComma + 1, secondComma).toInt());
      const long rawTargetCode = token.substring(secondComma + 1).toInt();

      if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule || rawTargetCode < 0 || rawTargetCode > 4095) {
        Serial.printf("[HTTP] 输出帧失败：非法模块或通道，模块=%u，通道=%u\n", moduleId, channelIndex);
        server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_frame_target\"}");
        return;
      }

      const uint16_t targetCode = static_cast<uint16_t>(rawTargetCode);
      smoothing_.setTarget(moduleId, channelIndex, targetCode);
      if (appliedCount == 0) {
        firstModuleId = moduleId;
        firstChannelIndex = channelIndex;
        firstTargetCode = targetCode;
      }
      ++appliedCount;
    }

    start = end + 1;
  }

  if (appliedCount == 0) {
    Serial.println("[HTTP] 输出帧失败：channels 为空");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"empty_frame\"}");
    return;
  }

  if ((frameId % 10L) == 1L) {
    Serial.printf("[HTTP] 输出帧：frame=%ld，通道数=%u，首通道=%u/%u->%u\n",
                  frameId,
                  static_cast<unsigned>(appliedCount),
                  firstModuleId,
                  firstChannelIndex,
                  firstTargetCode);
  }

  String json = "{\"ok\":true,\"frame_id\":";
  json += String(frameId);
  json += ",\"applied\":";
  json += String(appliedCount);
  json += "}";
  server_.send(200, "application/json", json);
}

void ApiServer::handleOutputs() {
  if (server_.hasArg("module_id") && server_.hasArg("channel_index") && server_.hasArg("target_code")) {
    const uint8_t moduleId = static_cast<uint8_t>(server_.arg("module_id").toInt());
    const uint8_t channelIndex = static_cast<uint8_t>(server_.arg("channel_index").toInt());
    const long rawTargetCode = server_.arg("target_code").toInt();

    if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule || rawTargetCode < 0 || rawTargetCode > 4095) {
      Serial.printf("[HTTP] 输出控制失败：非法模块/通道/目标码，模块=%u，通道=%u，目标码=%ld\n",
                    moduleId,
                    channelIndex,
                    rawTargetCode);
      server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_output_target\"}");
      return;
    }

    moduleBus_.refreshPresence(registry_);
    const RegistryEntry* entry = registry_.find(moduleId);
    if (entry == nullptr || !entry->registered) {
      Serial.printf("[HTTP] 输出控制失败：模块 %u 未注册\n", moduleId);
      server_.send(404, "application/json", "{\"ok\":false,\"error\":\"module_not_registered\"}");
      return;
    }
    if (!entry->present) {
      Serial.printf("[HTTP] 输出控制失败：模块 %u 当前离线\n", moduleId);
      server_.send(409, "application/json", "{\"ok\":false,\"error\":\"module_not_present\"}");
      return;
    }

    const uint16_t targetCode = static_cast<uint16_t>(rawTargetCode);
    smoothing_.setTarget(moduleId, channelIndex, targetCode);
    Serial.printf("[HTTP] 输出控制：模块=%u，通道=%u，目标码=%u\n", moduleId, channelIndex, targetCode);
    server_.send(200, "application/json", "{\"ok\":true}");
    return;
  }

  Serial.println("[HTTP] 输出控制失败：缺少 module_id/channel_index/target_code");
  sendTodo("batch_outputs_json");
}

void ApiServer::handlePreview() {
  if (!server_.hasArg("mode") || !server_.hasArg("module_id") || !server_.hasArg("channel_index") ||
      !server_.hasArg("target_code")) {
    Serial.println("[HTTP] 预览控制失败：缺少 mode/module_id/channel_index/target_code");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_preview_fields\"}");
    return;
  }

  const String mode = server_.arg("mode");
  if (mode != "locate" && mode != "calibration") {
    Serial.printf("[HTTP] 预览控制失败：非法 mode=%s\n", mode.c_str());
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_preview_mode\"}");
    return;
  }

  const uint8_t moduleId = static_cast<uint8_t>(server_.arg("module_id").toInt());
  const uint8_t channelIndex = static_cast<uint8_t>(server_.arg("channel_index").toInt());
  const uint16_t targetCode = static_cast<uint16_t>(server_.arg("target_code").toInt());

  if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule) {
    Serial.printf("[HTTP] 预览控制失败：非法模块或通道，模块=%u，通道=%u\n", moduleId, channelIndex);
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_preview_target\"}");
    return;
  }

  moduleBus_.refreshPresence(registry_);
  const RegistryEntry* entry = registry_.find(moduleId);
  if (entry == nullptr || !entry->registered) {
    Serial.printf("[HTTP] 预览控制失败：模块 %u 未注册\n", moduleId);
    server_.send(404, "application/json", "{\"ok\":false,\"error\":\"module_not_registered\"}");
    return;
  }
  if (!entry->present) {
    Serial.printf("[HTTP] 预览控制失败：模块 %u 当前离线\n", moduleId);
    server_.send(409, "application/json", "{\"ok\":false,\"error\":\"module_not_present\"}");
    return;
  }

  for (const RegistryEntry& current : registry_.entries()) {
    if (!current.registered) {
      continue;
    }
    for (uint8_t currentChannel = 0; currentChannel < kChannelsPerModule; ++currentChannel) {
      const bool highlighted = current.id == moduleId && currentChannel == channelIndex;
      smoothing_.setTarget(current.id, currentChannel, highlighted ? targetCode : 0, true, true);
    }
  }

  Serial.printf("[HTTP] 预览控制：模式=%s，模块=%u，通道=%u，目标码=%u，其它通道平滑归零，抖动=关闭\n",
                mode.c_str(),
                moduleId,
                channelIndex,
                targetCode);

  String json = "{\"ok\":true,\"preview_active\":true,\"mode\":\"";
  json += mode;
  json += "\",\"module_id\":";
  json += String(moduleId);
  json += ",\"channel_index\":";
  json += String(channelIndex);
  json += ",\"target_code\":";
  json += String(targetCode);
  json += "}";
  server_.send(200, "application/json", json);
}

void ApiServer::handleRegister() {
  if (!server_.hasArg("module_type") || !server_.hasArg("id") || !server_.hasArg("address")) {
    Serial.println("[HTTP] 模块注册失败：缺少 module_type / id / address");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_registration_fields\"}");
    return;
  }

  const ModuleType type = static_cast<ModuleType>(server_.arg("module_type").toInt());
  const uint8_t requestedID = static_cast<uint8_t>(server_.arg("id").toInt());
  const uint8_t sourceAddress = static_cast<uint8_t>(server_.arg("address").toInt());
  const uint8_t targetAddress = addressForID(requestedID);

  if (type != ModuleType::Radiance && type != ModuleType::Balance) {
    Serial.printf("[HTTP] 模块注册失败：非法 module_type=%u\n", static_cast<uint8_t>(type));
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_module_type\"}");
    return;
  }

  if (!isValidModuleID(requestedID) || targetAddress == 0) {
    Serial.printf("[HTTP] 模块注册失败：非法 id=%u\n", requestedID);
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_id\"}");
    return;
  }

  if (!isValidModuleAddress(sourceAddress)) {
    Serial.printf("[HTTP] 模块注册失败：非法来源地址 0x%02X\n", sourceAddress);
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_source_address\"}");
    return;
  }

  moduleBus_.refreshPresence(registry_);

  if (!moduleBus_.isAddressPresent(sourceAddress)) {
    Serial.printf("[HTTP] 模块注册失败：来源地址 0x%02X 未检测到设备\n", sourceAddress);
    server_.send(404, "application/json", "{\"ok\":false,\"error\":\"source_device_not_detected\"}");
    return;
  }

  const RegistryEntry* entry = registry_.find(requestedID);
  if (entry == nullptr) {
    Serial.printf("[HTTP] 模块注册失败：槽位 #%u 不存在\n", requestedID);
    server_.send(404, "application/json", "{\"ok\":false,\"error\":\"slot_not_found\"}");
    return;
  }

  if (entry->registered) {
    Serial.printf("[HTTP] 模块注册失败：槽位 #%u 已被占用\n", requestedID);
    server_.send(409, "application/json", "{\"ok\":false,\"error\":\"slot_occupied\"}");
    return;
  }

  for (const RegistryEntry& current : registry_.entries()) {
    if (!current.registered) {
      continue;
    }
    if (addressForID(current.id) == sourceAddress) {
      Serial.printf("[HTTP] 模块注册失败：来源地址 0x%02X 当前仍属于已注册槽位 #%u\n",
                    sourceAddress,
                    current.id);
      server_.send(409, "application/json", "{\"ok\":false,\"error\":\"source_address_belongs_to_registered_module\"}");
      return;
    }
  }

  bool firstSevenFull = true;
  for (uint8_t id = 1; id <= 7; ++id) {
    const RegistryEntry* slot = registry_.find(id);
    if (slot == nullptr || !slot->registered) {
      firstSevenFull = false;
      break;
    }
  }

  if (requestedID == 8) {
    if (!firstSevenFull) {
      Serial.println("[HTTP] 模块注册失败：前 7 个槽位未满，不能直接占用 0x60 保留槽位");
      server_.send(409, "application/json", "{\"ok\":false,\"error\":\"reserved_slot_not_allowed\"}");
      return;
    }
    if (sourceAddress != targetAddress) {
      if (moduleBus_.isAddressPresent(targetAddress)) {
        Serial.println("[HTTP] 模块注册失败：保留地址 0x60 已被占用");
        server_.send(409, "application/json", "{\"ok\":false,\"error\":\"reserved_address_busy\"}");
        return;
      }

      if (!dacDriver_.rewriteAddress(sourceAddress, targetAddress)) {
        Serial.printf("[HTTP] 模块注册失败：0x%02X -> 0x%02X 改址失败\n", sourceAddress, targetAddress);
        server_.send(500, "application/json", "{\"ok\":false,\"error\":\"address_rewrite_failed\"}");
        return;
      }
    }
    Serial.printf("[HTTP] 模块注册：将地址 0x%02X 的未知设备登记为最后一个槽位，类型=%u\n",
                  sourceAddress,
                  static_cast<uint8_t>(type));
  } else {
    if (firstSevenFull) {
      Serial.println("[HTTP] 模块注册失败：前 7 个槽位已满，请改用最后一个 0x60 保留槽位");
      server_.send(409, "application/json", "{\"ok\":false,\"error\":\"only_reserved_slot_available\"}");
      return;
    }

    if (sourceAddress != targetAddress && moduleBus_.isAddressPresent(targetAddress)) {
      Serial.printf("[HTTP] 模块注册失败：目标地址 0x%02X 已被占用\n", targetAddress);
      server_.send(409, "application/json", "{\"ok\":false,\"error\":\"target_address_busy\"}");
      return;
    }

    if (sourceAddress != targetAddress) {
      if (!dacDriver_.rewriteAddress(sourceAddress, targetAddress)) {
        Serial.printf("[HTTP] 模块注册失败：0x%02X -> 0x%02X 改址失败\n", sourceAddress, targetAddress);
        server_.send(500, "application/json", "{\"ok\":false,\"error\":\"address_rewrite_failed\"}");
        return;
      }
    }
  }

  registry_.setRegistered(requestedID, type, true);
  moduleBus_.refreshPresence(registry_);
  registry_.save();
  heartbeat_.markStateChanged();
  Serial.printf("[HTTP] 模块注册完成：ID=%u，地址=0x%02X，类型=%u\n",
                requestedID,
                targetAddress,
                static_cast<uint8_t>(type));
  server_.send(200, "application/json", buildStateJson());
}

void ApiServer::handleDelete() {
  if (!server_.hasArg("id")) {
    Serial.println("[HTTP] 删除模块失败：缺少 id");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_id\"}");
    return;
  }

  const uint8_t id = static_cast<uint8_t>(server_.arg("id").toInt());
  const RegistryEntry* entry = registry_.find(id);
  if (entry == nullptr || !entry->registered) {
    Serial.printf("[HTTP] 删除模块失败：ID=%u 不存在\n", id);
    server_.send(404, "application/json", "{\"ok\":false,\"error\":\"not_found\"}");
    return;
  }

  const uint8_t address = addressForID(id);
  if (entry->present) {
    Serial.printf("[HTTP] 删除模块：ID=%u 当前在线，先将地址 0x%02X 输出归零\n", id, address);
    dacDriver_.writeChannelCode(address, 0, 0);
    dacDriver_.writeChannelCode(address, 1, 0);
  }

  Serial.printf("[HTTP] 删除模块：ID=%u\n", id);
  smoothing_.clearModule(id);
  calibrationStore_.clearModule(id);
  calibrationStore_.save();
  registry_.clearSlot(id);
  registry_.save();
  heartbeat_.markStateChanged();
  handleState();
}

void ApiServer::handleReset() {
  if (!server_.hasArg("address")) {
    Serial.println("[HTTP] 重置未知设备失败：缺少 address");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_address\"}");
    return;
  }

  const uint8_t address = static_cast<uint8_t>(server_.arg("address").toInt());
  if (!isValidModuleAddress(address) || address == kUnknownModuleAddress) {
    Serial.printf("[HTTP] 重置未知设备失败：非法地址 0x%02X\n", address);
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_address\"}");
    return;
  }

  moduleBus_.refreshPresence(registry_);

  if (!moduleBus_.isAddressPresent(address)) {
    Serial.printf("[HTTP] 重置未知设备失败：地址 0x%02X 未检测到设备\n", address);
    server_.send(404, "application/json", "{\"ok\":false,\"error\":\"device_not_detected\"}");
    return;
  }

  for (const RegistryEntry& entry : registry_.entries()) {
    if (!entry.registered) {
      continue;
    }
    if (addressForID(entry.id) == address) {
      Serial.printf("[HTTP] 重置未知设备失败：地址 0x%02X 当前属于已注册槽位 #%u\n", address, entry.id);
      server_.send(409, "application/json", "{\"ok\":false,\"error\":\"address_belongs_to_registered_module\"}");
      return;
    }
  }

  if (moduleBus_.isAddressPresent(kUnknownModuleAddress)) {
    Serial.println("[HTTP] 重置未知设备失败：地址 0x60 已被占用");
    server_.send(409, "application/json", "{\"ok\":false,\"error\":\"fresh_address_busy\"}");
    return;
  }

  if (!dacDriver_.rewriteAddress(address, kUnknownModuleAddress)) {
    Serial.printf("[HTTP] 重置未知设备失败：0x%02X -> 0x60 改址失败\n", address);
    server_.send(500, "application/json", "{\"ok\":false,\"error\":\"address_reset_failed\"}");
    return;
  }

  delay(200);
  moduleBus_.refreshPresence(registry_);
  if (!moduleBus_.unknownCandidatePresent(registry_)) {
    Serial.println("[HTTP] 重置未知设备失败：改址后没有在 0x60 检测到新设备");
    server_.send(500, "application/json", "{\"ok\":false,\"error\":\"address_reset_verification_failed\"}");
    return;
  }

  Serial.printf("[HTTP] 重置未知设备成功：0x%02X -> 0x60\n", address);
  heartbeat_.markStateChanged();
  server_.send(200, "application/json", buildStateJson());
}

void ApiServer::handleI2CWriteAddress() {
  if (!server_.hasArg("old_address") || !server_.hasArg("new_address")) {
    Serial.println("[HTTP] I2C 改址失败：缺少 old_address 或 new_address");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_i2c_address_fields\"}");
    return;
  }

  const uint8_t oldAddress = static_cast<uint8_t>(server_.arg("old_address").toInt());
  const uint8_t newAddress = static_cast<uint8_t>(server_.arg("new_address").toInt());

  if (!isValidModuleAddress(oldAddress) || !isValidModuleAddress(newAddress)) {
    Serial.printf("[HTTP] I2C 改址失败：地址超出支持范围 old=0x%02X new=0x%02X\n", oldAddress, newAddress);
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"unsupported_i2c_address\"}");
    return;
  }

  moduleBus_.refreshPresence(registry_);
  if (!moduleBus_.isAddressPresent(oldAddress)) {
    Serial.printf("[HTTP] I2C 改址失败：旧地址 0x%02X 未检测到设备\n", oldAddress);
    server_.send(404, "application/json", "{\"ok\":false,\"error\":\"old_address_not_detected\"}");
    return;
  }

  if (oldAddress != newAddress && moduleBus_.isAddressPresent(newAddress)) {
    Serial.printf("[HTTP] I2C 改址失败：新地址 0x%02X 已被占用\n", newAddress);
    server_.send(409, "application/json", "{\"ok\":false,\"error\":\"new_address_busy\"}");
    return;
  }

  if (!dacDriver_.rewriteAddress(oldAddress, newAddress)) {
    Serial.printf("[HTTP] I2C 改址失败：0x%02X -> 0x%02X 底层写入失败\n", oldAddress, newAddress);
    server_.send(500, "application/json", "{\"ok\":false,\"error\":\"i2c_address_write_failed\"}");
    return;
  }

  delay(200);
  moduleBus_.refreshPresence(registry_);
  if (!moduleBus_.isAddressPresent(newAddress)) {
    Serial.printf("[HTTP] I2C 改址失败：改址后没有在 0x%02X 检测到设备\n", newAddress);
    server_.send(500, "application/json", "{\"ok\":false,\"error\":\"i2c_address_write_verification_failed\"}");
    return;
  }

  heartbeat_.markStateChanged();
  Serial.printf("[HTTP] I2C 改址成功：0x%02X -> 0x%02X（不自动修改注册表）\n", oldAddress, newAddress);
  server_.send(200, "application/json", buildStateJson());
}

void ApiServer::handleCalibrationSave() {
  if (!server_.hasArg("module_id") || !server_.hasArg("channel_index") || !server_.hasArg("points")) {
    Serial.println("[HTTP] LUT 保存失败：缺少 module_id / channel_index / points");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"missing_calibration_fields\"}");
    return;
  }

  const uint8_t moduleId = static_cast<uint8_t>(server_.arg("module_id").toInt());
  const uint8_t channelIndex = static_cast<uint8_t>(server_.arg("channel_index").toInt());
  const uint32_t updatedAtEpoch = server_.hasArg("updated_at_epoch")
      ? static_cast<uint32_t>(server_.arg("updated_at_epoch").toInt())
      : 0U;
  if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule) {
    Serial.println("[HTTP] LUT 保存失败：module_id 或 channel_index 非法");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_calibration_target\"}");
    return;
  }

  std::array<CalibrationPoint, kMaxLUTPoints> points{};
  uint8_t pointCount = 0;
  String remaining = server_.arg("points");

  while (remaining.length() > 0 && pointCount < kMaxLUTPoints) {
    const int separator = remaining.indexOf(';');
    const String token = separator >= 0 ? remaining.substring(0, separator) : remaining;
    remaining = separator >= 0 ? remaining.substring(separator + 1) : "";

    const int colon = token.indexOf(':');
    if (colon <= 0) {
      continue;
    }

    CalibrationPoint point;
    point.input = token.substring(0, colon).toFloat();
    point.output = token.substring(colon + 1).toFloat();
    points[pointCount++] = point;
  }

  if (pointCount < 2) {
    Serial.println("[HTTP] LUT 保存失败：有效点数量不足");
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"invalid_calibration_points\"}");
    return;
  }

  calibrationStore_.upsert(moduleId, channelIndex, points, pointCount, updatedAtEpoch);
  calibrationStore_.save();
  heartbeat_.markStateChanged();
  Serial.printf("[HTTP] LUT 保存成功：模块=%u，通道=%u，点数=%u\n", moduleId, channelIndex, pointCount);
  server_.send(200, "application/json", buildStateJson());
}

void ApiServer::handleFirmwareUpload() {
  HTTPUpload& upload = server_.upload();

  if (upload.status == UPLOAD_FILE_START) {
    firmwareUploadStarted_ = true;
    firmwareUploadSucceeded_ = false;
    firmwareUploadError_ = "";

    Serial.printf("[HTTP] 开始 OTA 上传：文件=%s\n", upload.filename.c_str());

    if (!Update.begin(UPDATE_SIZE_UNKNOWN, U_FLASH)) {
      firmwareUploadError_ = "update_begin_failed";
      Update.printError(Serial);
      return;
    }
    return;
  }

  if (!firmwareUploadStarted_ || !firmwareUploadError_.isEmpty()) {
    return;
  }

  if (upload.status == UPLOAD_FILE_WRITE) {
    const size_t written = Update.write(upload.buf, upload.currentSize);
    if (written != upload.currentSize) {
      firmwareUploadError_ = "update_write_failed";
      Update.printError(Serial);
    }
    return;
  }

  if (upload.status == UPLOAD_FILE_END) {
    if (Update.end(true)) {
      firmwareUploadSucceeded_ = true;
      heartbeat_.markStateChanged();
      Serial.printf("[HTTP] OTA 上传完成：总大小=%u 字节，即将重启\n", upload.totalSize);
    } else {
      firmwareUploadError_ = "update_finalize_failed";
      Update.printError(Serial);
    }
    return;
  }

  if (upload.status == UPLOAD_FILE_ABORTED) {
    firmwareUploadError_ = "upload_aborted";
    Update.abort();
    Serial.println("[HTTP] OTA 上传被中断");
  }
}

void ApiServer::finalizeFirmwareUpload() {
  if (!firmwareUploadStarted_) {
    server_.send(400, "application/json", "{\"ok\":false,\"error\":\"firmware_upload_not_started\"}");
    return;
  }

  firmwareUploadStarted_ = false;

  if (!firmwareUploadError_.isEmpty() || !firmwareUploadSucceeded_) {
    String json = "{\"ok\":false,\"error\":\"";
    json += firmwareUploadError_.isEmpty() ? "firmware_upload_failed" : firmwareUploadError_;
    json += "\"}";
    server_.send(500, "application/json", json);
    firmwareUploadSucceeded_ = false;
    firmwareUploadError_ = "";
    return;
  }

  String json = "{\"ok\":true,\"rebooting\":true,\"message\":\"固件上传成功，ESP32 正在重启。\",\"firmware_version\":\"";
  json += kFirmwareVersion;
  json += "\"}";
  server_.send(200, "application/json", json);
  delay(250);
  ESP.restart();
}

String ApiServer::buildStateJson() const {
  const DeviceSmoothingProfiles& config = smoothing_.configs();

  String json = "{";
  json += "\"device_name\":\"" + provisioning_.deviceName() + "\",";
  json += "\"firmware_version\":\"";
  json += kFirmwareVersion;
  json += "\",";
  json += "\"ip\":\"" + provisioning_.currentIP() + "\",";
  json += "\"mac\":\"" + WiFi.macAddress() + "\",";
  json += "\"state_revision\":";
  json += String(heartbeat_.stateRevision());
  json += ",";
  json += "\"heartbeat_interval_ms\":";
  json += String(heartbeat_.intervalMs());
  json += ",";
  json += "\"heartbeat_default_port\":";
  json += String(heartbeat_.defaultPort());
  json += ",";
  json += "\"heartbeat_target_port\":";
  json += String(heartbeat_.targetPort());
  json += ",";
  json += "\"heartbeat_configured_port\":";
  json += heartbeat_.configuredPort() ? "true" : "false";
  json += ",";
  json += "\"heartbeat_delivery\":\"";
  json += heartbeat_.delivery();
  json += "\",";
  json += "\"wifi_mode\":\"";
  json += provisioning_.isAccessPointMode() ? "ap" : "sta";
  json += "\",";
  json += "\"unknown_candidate_present\":";
  json += moduleBus_.unknownCandidatePresent(registry_) ? "true" : "false";
  json += ",";
  json += "\"detected_i2c_addresses\":[";

  bool firstDetected = true;
  for (uint8_t address = kUnknownModuleAddress;
       address < kUnknownModuleAddress + kMaxModules;
       ++address) {
    if (!moduleBus_.isAddressPresent(address)) {
      continue;
    }
    if (!firstDetected) {
      json += ",";
    }
    firstDetected = false;
    json += String(address);
  }

  json += "],";
  json += "\"unknown_i2c_addresses\":[";

  bool firstUnknown = true;
  for (uint8_t address = kUnknownModuleAddress;
       address < kUnknownModuleAddress + kMaxModules;
       ++address) {
    if (!moduleBus_.isAddressPresent(address)) {
      continue;
    }

    bool registered = false;
    for (const RegistryEntry& entry : registry_.entries()) {
      if (entry.registered && addressForID(entry.id) == address) {
        registered = true;
        break;
      }
    }

    if (registered) {
      continue;
    }

    if (!firstUnknown) {
      json += ",";
    }
    firstUnknown = false;
    json += String(address);
  }

  json += "],";
  json += "\"calibration_luts\":[";

  bool firstLUT = true;
  for (const CalibrationLUTProfile& lut : calibrationStore_.entries()) {
    if (!lut.valid || lut.pointCount < 2) {
      continue;
    }

    if (!firstLUT) {
      json += ",";
    }
    firstLUT = false;
    json += "{";
    json += "\"module_id\":";
    json += String(lut.moduleId);
    json += ",\"channel_index\":";
    json += String(lut.channelIndex);
    json += ",\"updated_at_epoch\":";
    json += String(lut.updatedAtEpoch);
    json += ",\"points\":[";

    for (uint8_t index = 0; index < lut.pointCount; ++index) {
      if (index > 0) {
        json += ",";
      }
      json += "{\"input\":";
      json += String(lut.points[index].input, 4);
      json += ",\"output\":";
      json += String(lut.points[index].output, 4);
      json += "}";
    }
    json += "]}";
  }

  json += "],";
  json += "\"smoothing\":{\"radiance\":{\"settle_time_ms\":";
  json += String(config.radiance.settleTimeMs);
  json += ",\"a_max\":";
  json += String(config.radiance.aMax, 3);
  json += ",\"v_max\":";
  json += String(config.radiance.vMax, 3);
  json += ",\"jitter_frequency_hz\":";
  json += String(config.radiance.jitterFrequencyHz, 3);
  json += ",\"jitter_amplitude\":";
  json += String(config.radiance.jitterAmplitude, 3);
  json += ",\"jitter_dispersion\":";
  json += String(config.radiance.jitterDispersion, 3);
  json += "},\"balance\":{\"settle_time_ms\":";
  json += String(config.balance.settleTimeMs);
  json += ",\"a_max\":";
  json += String(config.balance.aMax, 3);
  json += ",\"v_max\":";
  json += String(config.balance.vMax, 3);
  json += ",\"jitter_frequency_hz\":";
  json += String(config.balance.jitterFrequencyHz, 3);
  json += ",\"jitter_amplitude\":";
  json += String(config.balance.jitterAmplitude, 3);
  json += ",\"jitter_dispersion\":";
  json += String(config.balance.jitterDispersion, 3);
  json += "}},";
  json += "\"modules\":[";

  bool first = true;
  for (const RegistryEntry& entry : registry_.entries()) {
    if (!first) {
      json += ",";
    }
    first = false;

    json += "{";
    json += "\"id\":";
    json += String(entry.id);
    json += ",\"registered\":";
    json += entry.registered ? "true" : "false";
    json += ",\"present\":";
    json += entry.present ? "true" : "false";
    json += ",\"module_type\":";
    json += String(static_cast<uint8_t>(entry.moduleType));
    json += "}";
  }

  json += "]}";
  return json;
}

void ApiServer::sendTodo(const char* action) {
  String json = "{\"ok\":false,\"error\":\"todo\",\"action\":\"";
  json += action;
  json += "\"}";
  server_.send(501, "application/json", json);
}

}  // namespace orb
