#pragma once
#include <M5StickCPlus.h>

#define FIRMWARE_VERSION "1.0"

// Hardcoded maximum camera count, either 4 or 8
#define CAMERA_COUNT 4

// Single byte XOR key for basic encoding
#define PACKET_XOR_KEY 0x67

#define MODE_HOST 0
#define MODE_CAMERA_1 1
#define MODE_CAMERA_2 2
#define MODE_CAMERA_3 3
#define MODE_CAMERA_4 4
#define MODE_CAMERA_5 5
#define MODE_CAMERA_6 6
#define MODE_CAMERA_7 7
#define MODE_CAMERA_8 8

#define TEST_MODE_TIME 2000

#define CAMERA_STATUS_STANDBY 0
#define CAMERA_STATUS_PREVIEW 1
#define CAMERA_STATUS_PROGRAM 2

class System {
public:
    static void begin();

    static void update(uint32_t ms);

    static uint8_t getMode();

    static void setMode(uint8_t val);

    static const String& getErrorMsg();

    static void sendStatusMessage();

    static void sendTestMessage(uint8_t target = 0xff, bool immediately = false);

    static bool isInTestMode();

    static void powerOff();

    static const uint8_t *getCameraStatus();

    static const uint8_t getCurrentCameraStatus();

    static bool getIsAudioEnabled();

    static void setIsAudioEnabled(bool val);

    static uint8_t getBrightness();

    static void setBrightness(uint8_t val);
};