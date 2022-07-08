#include <M5StickCPlus.h>
#include "system.h"
#include "gui.h"

void setup() {
    System::begin();
    GUI::begin();
}

void loop() {
    uint32_t ms = millis();

    System::update(ms);
    GUI::update(ms);
    delay(1);
}