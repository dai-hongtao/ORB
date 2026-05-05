#pragma once

#include <WebServer.h>

#include "MCP4728Driver.h"
#include "ModuleBus.h"
#include "RegistryStore.h"
#include "SmoothingEngine.h"
#include "HeartbeatService.h"
#include "WiFiProvisioning.h"
#include "CalibrationStore.h"

namespace orb {

class ApiServer {
 public:
  ApiServer(
      RegistryStore& registry,
      CalibrationStore& calibrationStore,
      ModuleBus& moduleBus,
      MCP4728Driver& dacDriver,
      SmoothingEngine& smoothing,
      HeartbeatService& heartbeat,
      WiFiProvisioning& provisioning);

  void begin();
  void handleClient();

 private:
  void handlePing();
  void handleHeartbeatConfig();
  void handleState();
  void handleSmoothing();
  void handleFrame();
  void handleOutputs();
  void handlePreview();
  void handleRegister();
  void handleDelete();
  void handleReset();
  void handleI2CWriteAddress();
  void handleCalibrationSave();
  void handleFirmwareUpload();
  void finalizeFirmwareUpload();

  String buildStateJson() const;
  void sendTodo(const char* action);

  RegistryStore& registry_;
  CalibrationStore& calibrationStore_;
  ModuleBus& moduleBus_;
  MCP4728Driver& dacDriver_;
  SmoothingEngine& smoothing_;
  HeartbeatService& heartbeat_;
  WiFiProvisioning& provisioning_;
  WebServer server_;
  bool firmwareUploadStarted_ = false;
  bool firmwareUploadSucceeded_ = false;
  String firmwareUploadError_;
};

}  // namespace orb
