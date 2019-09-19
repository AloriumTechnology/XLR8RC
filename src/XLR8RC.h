/*
 * Copyright (c) 2019 Alorium Technology
 * Bryan Craker, info@aloriumtech.com
 *
 * RC library for use with the RC XB on an XLR8 family board.
 *
 * MIT License
 */

#ifndef XLR8_RC_H
#define XLR8_RC_H

#ifdef ARDUINO_XLR8

#include <Arduino.h>

#define RCCR  _SFR_MEM8(0xe4)
#define RCPWH _SFR_MEM8(0xe5)
#define RCPWL _SFR_MEM8(0xe6)

#define RCEN  7
#define RCDIS 6

#define RCPIN 3

#define MAX_RCS 32
#define INVALID_RC 255

typedef struct {
  uint16_t pwm_recv;
  bool     en;
} RCSettings_t;

typedef struct {
  RCSettings_t settings;
} rc_t;

class XLR8RC {
public:
  XLR8RC();
  void enable();
  void disable();
  uint16_t getPwm();
  bool isEnabled();
private:
  uint8_t rcIndex;
  void init();
};

#else
#error "XLR8RC library requires Tools->Board->XLR8xxx selection."
#endif // ARDUINO_XLR8

#endif // XLR8_RC_H
