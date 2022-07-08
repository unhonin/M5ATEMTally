#pragma once
#include <M5StickCPlus.h>

#define ENC_BUTTONINTERVAL    50  // check button every x milliseconds, also debouce time
#define ENC_DOUBLECLICKTIME  600  // second click within 600ms
#define ENC_HOLDTIME        500  // report held button after 1.2s

class ButtonReader {
public:
    typedef enum Button_e {
        Open = 0,
        Closed,
        
        Pressed,
        Held,
        Released,
        
        Clicked,
        DoubleClicked
        
    } ButtonState;

    ButtonReader(Button *_button)
        : button(_button),
        keyDownTicks(0),
        doubleClickTicks(0),
        lastButtonCheck(0),
        doubleClickEnabled(false),
        value(Open) {
    }

    ButtonState get() {
        ButtonReader::ButtonState ret = value;
        if (value != ButtonReader::Held) {
            value = ButtonReader::Open; // reset
        }
        return ret;
    }

    void update() {
        unsigned long now = millis();

        lastButtonCheck = now;
        auto state = button->read();
        
        if (state) { // key is down
            keyDownTicks++;
            if (keyDownTicks > (ENC_HOLDTIME / ENC_BUTTONINTERVAL)) {
                value = Held;
            }
        }

        if (!state) { // key is now up
            if (keyDownTicks /*> ENC_BUTTONINTERVAL*/) {
                if (value == Held) {
                    value = Released;
                    doubleClickTicks = 0;
                }
                else {
                    #define ENC_SINGLECLICKONLY 1
                    if (doubleClickTicks > ENC_SINGLECLICKONLY) {   // prevent trigger in single click mode
                        if (doubleClickTicks < (ENC_DOUBLECLICKTIME / ENC_BUTTONINTERVAL)) {
                            value = DoubleClicked;
                            doubleClickTicks = 0;
                        }
                    }
                    else {
                        doubleClickTicks = (doubleClickEnabled) ? (ENC_DOUBLECLICKTIME / ENC_BUTTONINTERVAL) : ENC_SINGLECLICKONLY;
                    }
                }
            }

            keyDownTicks = 0;
        }
    
        if (doubleClickTicks > 0) {
            //doubleClickTicks--;
            if (--doubleClickTicks == 0) {
                value = Clicked;
            }
        }
    }

private:
    uint16_t keyDownTicks;
    uint8_t doubleClickTicks;
    unsigned long lastButtonCheck;
    volatile ButtonState value;
    bool doubleClickEnabled;
    Button *button;
};