#include "MCP4728Driver.h"

#include "Config.h"

namespace orb {

namespace {
bool multiWriteOne(TwoWire& wire, uint8_t address, uint8_t channel, uint16_t code) {
  channel &= 0x03;
  code &= 0x0FFF;

  const uint8_t dac1 = (channel >> 1) & 0x01;
  const uint8_t dac0 = channel & 0x01;
  const uint8_t command = static_cast<uint8_t>(0b01000000 | (dac1 << 2) | (dac0 << 1));
  const uint8_t byte3 = static_cast<uint8_t>((code >> 8) & 0x0F);
  const uint8_t byte4 = static_cast<uint8_t>(code & 0xFF);

  wire.beginTransmission(address);
  wire.write(command);
  wire.write(byte3);
  wire.write(byte4);
  return wire.endTransmission(true) == 0;
}

constexpr int kI2CRewriteDelayUs = 8;

void sdaLow() {
  pinMode(kPinI2CSDA, OUTPUT);
  digitalWrite(kPinI2CSDA, LOW);
}

void sdaRelease() {
  pinMode(kPinI2CSDA, INPUT);
}

void sclLow() {
  pinMode(kPinI2CSCL, OUTPUT);
  digitalWrite(kPinI2CSCL, LOW);
}

void sclRelease() {
  pinMode(kPinI2CSCL, INPUT);
}

bool sdaRead() {
  pinMode(kPinI2CSDA, INPUT);
  return digitalRead(kPinI2CSDA);
}

void ldacHigh() {
  digitalWrite(kPinMcpLdac, HIGH);
}

void ldacLow() {
  digitalWrite(kPinMcpLdac, LOW);
}

void i2cDelay() {
  delayMicroseconds(kI2CRewriteDelayUs);
}

void bbInitBus() {
  sdaRelease();
  sclRelease();
  i2cDelay();
}

void bbStart() {
  sdaRelease();
  sclRelease();
  i2cDelay();
  sdaLow();
  i2cDelay();
  sclLow();
  i2cDelay();
}

void bbStop() {
  sdaLow();
  i2cDelay();
  sclRelease();
  i2cDelay();
  sdaRelease();
  i2cDelay();
}

bool bbWriteBit(bool bitVal) {
  if (bitVal) {
    sdaRelease();
  } else {
    sdaLow();
  }

  i2cDelay();
  sclRelease();
  i2cDelay();
  sclLow();
  i2cDelay();
  return true;
}

bool bbReadAck() {
  sdaRelease();
  i2cDelay();
  sclRelease();
  i2cDelay();
  const bool ack = !sdaRead();
  sclLow();
  i2cDelay();
  return ack;
}

bool bbWriteByteNormal(uint8_t data) {
  for (int i = 7; i >= 0; --i) {
    bbWriteBit((data >> i) & 0x01);
  }
  return bbReadAck();
}

bool bbWriteByte2WithLdacDrop(uint8_t data) {
  for (int i = 7; i >= 0; --i) {
    bbWriteBit((data >> i) & 0x01);
  }

  ldacLow();
  i2cDelay();
  return bbReadAck();
}

bool rewriteAddressBits(uint8_t oldAddress, uint8_t newAddress) {
  const uint8_t oldA = oldAddress & 0x07;
  const uint8_t newA = newAddress & 0x07;

  const uint8_t byte1 = static_cast<uint8_t>(0xC0 | (oldA << 1));
  const uint8_t byte2 = static_cast<uint8_t>(0b01100001 | (oldA << 2));
  const uint8_t byte3 = static_cast<uint8_t>(0b01100010 | (newA << 2));
  const uint8_t byte4 = static_cast<uint8_t>(0b01100011 | (newA << 2));

  Serial.printf("[I2C] 准备改址：0x%02X -> 0x%02X\n", oldAddress, newAddress);

  ldacHigh();
  delayMicroseconds(20);

  bbInitBus();
  bbStart();

  const bool ack1 = bbWriteByteNormal(byte1);
  Serial.printf("[I2C] 改址 ACK1=%s\n", ack1 ? "YES" : "NO");
  if (!ack1) {
    bbStop();
    ldacHigh();
    return false;
  }

  const bool ack2 = bbWriteByte2WithLdacDrop(byte2);
  Serial.printf("[I2C] 改址 ACK2=%s\n", ack2 ? "YES" : "NO");
  if (!ack2) {
    bbStop();
    ldacHigh();
    return false;
  }

  const bool ack3 = bbWriteByteNormal(byte3);
  Serial.printf("[I2C] 改址 ACK3=%s\n", ack3 ? "YES" : "NO");
  if (!ack3) {
    bbStop();
    ldacHigh();
    return false;
  }

  const bool ack4 = bbWriteByteNormal(byte4);
  Serial.printf("[I2C] 改址 ACK4=%s\n", ack4 ? "YES" : "NO");
  bbStop();
  ldacHigh();

  if (!ack4) {
    return false;
  }

  delay(120);
  return true;
}
}  // namespace

void MCP4728Driver::begin(TwoWire& wire) {
  wire_ = &wire;
  pinMode(kPinMcpLdac, OUTPUT);
  ldacHigh();
}

bool MCP4728Driver::probe(uint8_t address) const {
  if (wire_ == nullptr) {
    return false;
  }

  wire_->beginTransmission(address);
  return wire_->endTransmission(true) == 0;
}

bool MCP4728Driver::writeChannelCode(uint8_t address, uint8_t channel, uint16_t code) const {
  if (wire_ == nullptr) {
    return false;
  }

  const bool ok = multiWriteOne(*wire_, address, channel, code);
  if (!ok) {
    Serial.printf("[I2C] DAC 写入失败：地址=0x%02X，通道=%u，目标码=%u\n",
                  address,
                  channel,
                  code);
  }
  return ok;
}

bool MCP4728Driver::rewriteAddress(uint8_t oldAddress, uint8_t newAddress) const {
  if (wire_ == nullptr) {
    Serial.println("[I2C] 改址失败：I2C 尚未初始化");
    return false;
  }

  if (!isValidModuleAddress(oldAddress) || !isValidModuleAddress(newAddress)) {
    Serial.printf("[I2C] 改址失败：非法地址 old=0x%02X new=0x%02X\n", oldAddress, newAddress);
    return false;
  }

  if (oldAddress == newAddress) {
    Serial.printf("[I2C] 改址跳过：地址已是 0x%02X\n", oldAddress);
    return true;
  }

  wire_->end();
  const bool rewriteOk = rewriteAddressBits(oldAddress, newAddress);
  wire_->begin(kPinI2CSDA, kPinI2CSCL, kI2CFrequencyHz);

  if (!rewriteOk) {
    return false;
  }

  const bool probeOk = probe(newAddress);
  Serial.printf("[I2C] 改址结果：%s\n", probeOk ? "成功" : "失败");
  return probeOk;
}

}  // namespace orb
