# XLR8RC

Captures outputs from an RC receiver (the signals that go to servos) and outputs a 16 bit integer representing the pulse width (in microseconds)

The output can be used for other functions; for instance, controlling the speed of a DC motor, or the brightness of an LED

It supports up to 32 independent channels with microsecond resolution

Functions include:
* enable() - turns on the specified channel
* disable() - turns off the specified channel
* getPwm() - returns uint16_t representing the pulsewidth
* isEnabled() - returns boolean representing whether the channel is enabled
