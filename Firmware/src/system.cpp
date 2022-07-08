#include <M5StickCPlus.h>
#include <Preferences.h>
#include <WiFi.h>
#include <esp_now.h>
#include <FastLED.h>
#include "CRC.h"
#include "system.h"
#include "esp_private/wifi.h"

#define EXTERNAL_LED_PIN 32
#define EXTERNAL_LED_NUM 4

Preferences preferences;
CRGB leds[EXTERNAL_LED_NUM];

#define PREF_LIB "pref_lib"
#define PREF_MODE_NAME "p_mode"
#define PREF_AUDIO_NAME "p_audio"
#define PREF_BRIGHTNESS_NAME "p_brignes"
#define MESSAGE_INTERVAL 33
#define AUTOSHUTDOWN_TIME 15000

#define MSG_TEST 0x01
#define MSG_STATUS 0x02
#define MSG_PING 0x03
#define MSG_PONG 0x04

#define MSG_OK 0x00
#define MSG_ERROR 0xFF

const uint8_t broadcastAddress[ESP_NOW_ETH_ALEN] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

uint8_t mode = MODE_CAMERA_1;
String errorMsg = "";

bool isTimeToSendTestMessage = false;
uint8_t testMessageFlag = 0;

uint8_t brightness = 2;
const uint8_t brightnessScales[] = {40, 82, 177, 219, 255};

bool isTestMode = false;
bool isAudioEnabled = true;
uint32_t testModeInitiateTime = 0;
uint32_t lastTestBeepTime = 0;
uint32_t lastReceivedTime = 0;
uint32_t lastMessageSentTime = 0;

uint32_t lastAlertBeepTime = 0;
int8_t alertCountRemaining = 0;

uint32_t lastLedUpdateTime = 0;

uint8_t cameraStatus[8] = {
    CAMERA_STATUS_STANDBY,
    CAMERA_STATUS_STANDBY,
    CAMERA_STATUS_STANDBY, 
    CAMERA_STATUS_STANDBY
#if CAMERA_COUNT > 4
    ,
    CAMERA_STATUS_STANDBY,
    CAMERA_STATUS_STANDBY,
    CAMERA_STATUS_STANDBY,
    CAMERA_STATUS_STANDBY
#endif
};

esp_err_t registerPeer(const uint8_t *address) {
    esp_now_peer_info_t peerData = {
        .peer_addr = {0},
        .lmk = {0},
        .channel = 0,
        .ifidx = WIFI_IF_STA,
        .encrypt = false,
        .priv = NULL
    };
    memcpy(peerData.peer_addr, address, ESP_NOW_ETH_ALEN);
    return esp_now_add_peer(&peerData);
}

esp_err_t broadcastSend(uint8_t *buf) {
    uint8_t len = buf[0];
    for (uint8_t i = 0; i < len; ++i) {
        buf[i] = buf[i] ^ PACKET_XOR_KEY;
    }
    return esp_now_send(broadcastAddress, buf, len);
}

uint8_t* hexStringToBytes(const char* string, size_t *len) {
    if (string == NULL) {
       return NULL;
    }

    size_t slength = strlen(string);
    if ((slength % 2) != 0) {// must be even
       return NULL;
    }

    size_t dlength = slength / 2;
    *len = dlength;

    uint8_t* data = new uint8_t[dlength];
    memset(data, 0, dlength);

    size_t index = 0;
    while (index < slength) {
        char c = string[index];
        int value = 0;
        if (c >= '0' && c <= '9')
          value = (c - '0');
        else if (c >= 'A' && c <= 'F') 
          value = (10 + (c - 'A'));
        else if (c >= 'a' && c <= 'f')
          value = (10 + (c - 'a'));
        else {
          delete [] data;
          return NULL;
        }

        data[(index/2)] += value << (((index + 1) % 2) * 4);
        index++;
    }

    return data;
}

char *bytesToHexString(const uint8_t *bin, uint32_t binsz) {
    const char hex_str[] = "0123456789abcdef";
    uint32_t i;

    if (!binsz) {
        return NULL;
    }
    char *result = new char[binsz * 2 + 2];
    if (result == NULL) {
        return NULL;
    }
    result[binsz * 2] = '\n';
    result[binsz * 2 + 1] = 0;

    for (i = 0; i < binsz; i++) {
        result[i * 2 + 0] = hex_str[(bin[i] >> 4) & 0x0F];
        result[i * 2 + 1] = hex_str[(bin[i]     ) & 0x0F];
    }
    return result;
}

void onDataReceived(const uint8_t *address, const uint8_t *src_data, int len) {
    uint8_t data[64] = {0};
    if (len >= 64) {
        return;
    }

    for (int i = 0; i < len; ++i) {
        data[i] = src_data[i] ^ PACKET_XOR_KEY;
    }

    if (mode == MODE_HOST || len < 4 || data[0] != len) {
        return;
    }

    uint16_t crc = crc16(data, len - 2);
    if (*(uint16_t *)&data[len - 2] != crc) {
        errorMsg = "CRC failed";
        return;
    }

    uint16_t type = data[1];
    if (type == MSG_TEST) {
        if (len != 5) {
            errorMsg = "Invalid len";
            return;
        }
        if (mode == MODE_HOST) {
            return;
        }
        if ((data[2] & (1 << (mode - 1))) != 0) {
            testModeInitiateTime = millis();
            isTestMode = true;
        }
    } else if (type == MSG_STATUS) {
        if (len != data[2] + 5) {
            errorMsg = "Invalid status";
            return;
        }

        uint8_t lastStatus = System::getCurrentCameraStatus();
        uint8_t count = min(CAMERA_COUNT, data[2]);
        for (uint8_t i = 0; i < count; ++i) {
            cameraStatus[i] = data[3 + i];
        }

        if (isAudioEnabled) {
            if (lastStatus != CAMERA_STATUS_PROGRAM && System::getCurrentCameraStatus() == CAMERA_STATUS_PROGRAM) {
                alertCountRemaining = 2;
            } else if (lastStatus == CAMERA_STATUS_PROGRAM && System::getCurrentCameraStatus() != CAMERA_STATUS_PROGRAM) {
                alertCountRemaining = 1;
            } 
        }
    }

    lastReceivedTime = millis();
}

void System::begin() {
    M5.begin(true, true, false);
    M5.Beep.setBeep(2000, 50);
    Serial.begin(115200);
    Serial.setTimeout(100);
    Serial.flush();
    delay(100);

    pinMode(26, OUTPUT);
    digitalWrite(26, HIGH);

    FastLED.addLeds<NEOPIXEL, EXTERNAL_LED_PIN>(leds, EXTERNAL_LED_NUM);

    WiFi.mode(WIFI_MODE_STA);
    esp_wifi_internal_set_fix_rate(WIFI_IF_STA, true, WIFI_PHY_RATE_LORA_250K);
    esp_wifi_set_protocol(WIFI_IF_STA, WIFI_PROTOCOL_LR);

    preferences.begin(PREF_LIB);

    if (preferences.isKey(PREF_MODE_NAME)) {
        mode = preferences.getUChar(PREF_MODE_NAME, MODE_CAMERA_1);
    }

    if (preferences.isKey(PREF_AUDIO_NAME)) {
        isAudioEnabled = preferences.getBool(PREF_AUDIO_NAME, true);
    }

    if (preferences.isKey(PREF_BRIGHTNESS_NAME)) {
        brightness = preferences.getUChar(PREF_BRIGHTNESS_NAME, 2);
    }

    if (esp_now_init() != ESP_OK) {
        errorMsg = "E-ESP-NOW";
        return;
    }

    esp_now_register_recv_cb(onDataReceived);

    if (mode == MODE_HOST) {
        registerPeer(broadcastAddress);
    }
}

uint8_t System::getMode() {
    return mode;
}

void System::setMode(uint8_t val) {
    mode = val;
    preferences.putUChar(PREF_MODE_NAME, mode);
}

const String& System::getErrorMsg() {
    return errorMsg;
}

void processCommands(const uint8_t *data, size_t len) {
    uint8_t buf[128] = {0};

    if (len < 4 || data[0] != len) {
        return;
    }

    uint16_t crc = crc16(data, len - 2);
    if (*(uint16_t *)&data[len - 2] != crc) {
        char str[64];
        sprintf(str, "crc %04x:%02x%02x%02x%02x", crc, data[0], data[1], data[2], data[3]);
        errorMsg = str;
        return;
    }

    uint16_t type = data[1];
    if (type == MSG_TEST) {
        buf[0] = 4;
        buf[1] = MSG_OK;

        if (len != 5) {
            buf[1] = MSG_ERROR;
        } else {
            System::sendTestMessage(data[2]);
        }
    } else if (type == MSG_STATUS) {
        buf[0] = 4;
        buf[1] = MSG_OK;

        if (len != data[2] + 5) {
            buf[1] = MSG_ERROR;
        } else {
            uint8_t count = min(CAMERA_COUNT, data[2]);
            for (uint8_t i = 0; i < count; ++i) {
                cameraStatus[i] = data[3 + i];
            }
        }
    } else if (type == MSG_PING) {
        buf[0] = 4;
        buf[1] = MSG_PONG;

        if (len != 4) {
            buf[1] = MSG_ERROR;
        }
    } 

    crc = crc16(buf, buf[0] - 2);
    memcpy(&buf[buf[0] - 2], &crc, 2);
    const char *hexData = bytesToHexString(buf, buf[0]);
    if (hexData != NULL) {
        delay(20);
        Serial.write(hexData);
        delete [] hexData;
    }
}

void System::update(uint32_t ms) {
    if (mode == MODE_HOST) {
        if (Serial.available()) {
            const String& str = Serial.readStringUntil('\n');
            if (str.length() > 0) {
                size_t length = 0;
                const uint8_t *data = hexStringToBytes(str.c_str(), &length);
                if (data != NULL) {
                    processCommands(data, length);
                    delete [] data;
                }
            }
        }
        
        if (ms - lastMessageSentTime > MESSAGE_INTERVAL) {
            if (isTimeToSendTestMessage) {
                System::sendTestMessage(testMessageFlag, true);
                isTimeToSendTestMessage = false;
            } else {
                sendStatusMessage();
            }

            lastMessageSentTime = ms;
        }
    }

    if (isTestMode && millis() - testModeInitiateTime <= TEST_MODE_TIME) {
        if (ms - lastTestBeepTime >= 400) {
            M5.Beep.beep();
            lastTestBeepTime = ms;
        }
    } else {
        isTestMode = false;
    }

    if (alertCountRemaining > 0) {
        if (ms - lastAlertBeepTime >= 150) {
            M5.Beep.beep();
            lastAlertBeepTime = ms;
            alertCountRemaining--;
        }
    }

    if (ms - lastLedUpdateTime > 30) {
        auto mode = System::getMode();
        auto status = System::getCurrentCameraStatus();

        if (System::isInTestMode()) {
            leds[0] = leds[1] = leds[2] = leds[3] = CRGB::Yellow;
            FastLED.show(brightnessScales[brightness]);
        } else {
            if (mode != MODE_HOST) {
                if (status == CAMERA_STATUS_PREVIEW) {
                    leds[0] = leds[1] = leds[2] = leds[3] = CRGB::Green;
                    FastLED.show(brightnessScales[brightness]);
                } else if (status == CAMERA_STATUS_PROGRAM) {
                    leds[0] = leds[1] = leds[2] = leds[3] = CRGB::Red;
                    FastLED.show(brightnessScales[brightness]);
                } else {
                    FastLED.clear(true);
                }
            } else {
                FastLED.clear(true);
            }
        }

        lastLedUpdateTime = ms;
    }

	M5.Beep.update();
}

void System::sendStatusMessage() {
    uint8_t buf[16] = { 0 };

    buf[0] = 5 + CAMERA_COUNT;
    buf[1] = MSG_STATUS;
    buf[2] = CAMERA_COUNT;
    for (uint8_t i = 0; i < CAMERA_COUNT; ++i) {
        buf[3 + i] = cameraStatus[i];
    }

    uint16_t crc = crc16(buf, CAMERA_COUNT + 3);
    memcpy(&buf[3 + CAMERA_COUNT], &crc, 2);

    broadcastSend(buf);
}

void System::sendTestMessage(uint8_t target, bool immediately) {
    uint8_t buf[] = {
        5,
        MSG_TEST,
        target,
        0,
        0
    };

    if (!immediately) {
        isTimeToSendTestMessage = true;
        testMessageFlag = target;
        return;
    }

    testModeInitiateTime = millis();
    isTestMode = true;

    uint16_t crc = crc16(buf, 3);
    memcpy(&buf[3], &crc, 2);

    broadcastSend(buf);
}

bool System::isInTestMode() {
    return (isTestMode && millis() - testModeInitiateTime <= TEST_MODE_TIME);
}

void System::powerOff() {
    M5.Axp.PowerOff();
}

const uint8_t *System::getCameraStatus() {
    return cameraStatus;
}

const uint8_t System::getCurrentCameraStatus() {
    if (mode == MODE_HOST) {
        return 0xff;
    }

    return cameraStatus[mode - 1];
}

bool System::getIsAudioEnabled() {
    return isAudioEnabled;
}

void System::setIsAudioEnabled(bool val) {
    isAudioEnabled = val;
    preferences.putBool(PREF_AUDIO_NAME, isAudioEnabled);
}

uint8_t System::getBrightness() {
    return brightness;
}

void System::setBrightness(uint8_t val){
    brightness = val;
}