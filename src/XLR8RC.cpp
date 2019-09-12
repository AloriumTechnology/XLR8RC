#include "XLR8RC.h"

static rc_t rcs[MAX_RCS];

uint8_t RcCount = 0;

XLR8RC::XLR8RC() {
  if (RcCount < MAX_RCS) {
    this->rcIndex = RcCount++;
    rcs[this->rcIndex].settings.pwm_recv = 0;
    rcs[this->rcIndex].settings.en = false;
    this->init();
  }
  else {
    this->rcIndex = INVALID_RC; // too many rcs
  }
}

void XLR8RC::enable() {
  rcs[this->rcIndex].settings.en = true;
  RCCR = (1 << RCEN) | (0x1f & this->rcIndex);
}

void XLR8RC::disable() {
  rcs[this->rcIndex].settings.en = false;
  RCCR = (1 << RCDIS) | (0x1f & this->rcIndex);
}

uint16_t XLR8RC::getPwm() {
  this->enable();
  rcs[this->rcIndex].settings.pwm_recv = ((uint16_t)(RCPWH << 8)) | (RCPWL);
  return rcs[this->rcIndex].settings.pwm_recv;
}

bool XLR8RC::isEnabled() {
  return rcs[this->rcIndex].settings.en;
}

void XLR8RC::init() {
  pinMode(RCPIN, INPUT);
}

