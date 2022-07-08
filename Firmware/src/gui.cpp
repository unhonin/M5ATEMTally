#include <M5StickCPlus.h>
#include <WiFi.h>
#include "MenuItem.h"
#include "buttonreader.h"
#include "xbmimages.h"
#include "gui.h"
#include "system.h"

TFT_eSprite sprite = TFT_eSprite(&M5.Lcd);
ButtonReader btnA(&M5.BtnA);

#define STATE_BOOTING 0
#define STATE_NORMAL 1
#define STATE_MENU 2

#define MONITOR_UPDATE_DELAY 30
#define LOGIC_UPDATE_DELAY 50
#define BOOTING_DELAY_DEFAULT 1500
#define BTN_ENTER_DELAY 1500

uint32_t bootingDelay = BOOTING_DELAY_DEFAULT;
uint32_t lastMonitorUpdateMS = 0;
uint32_t lastLogicUpdateMS = 0;
uint32_t lastBtnReleasedMs = 0;
uint32_t currentState = STATE_BOOTING;
uint32_t lastStateMS = 0;

MenuItem *rootMenu = NULL;
MenuItem *currentMenu = NULL;
int32_t currentMenuSelection = 0;
int32_t currentMenuViewPos = 0;
bool isModifyingSelection = false;
bool isLongPressedBefore = false;

const char *ModeOptions[] = { "Host", "Camera 1", "Camera 2", "Camera 3", "Camera 4",
	"Camera 5", "Camera 6", "Camera 7", "Camera 8" };
const char *AudioOptions[] = { "On", "Off" };
const char *BrightnessOptions[] = { "1", "2", "3", "4", "5" };

void GUI::begin() {
    sprite.createSprite(135, 240);

	rootMenu = new MenuItem("Menu");
	{
        auto modeMenu = new MenuItem("Mode", NULL);
        modeMenu->setTypeToSelection(System::getMode(), ModeOptions, CAMERA_COUNT + 1);
		modeMenu->setCallback([](MenuItem *item, bool isManually) -> void {
            System::setMode(item->selection);
		});
		rootMenu->addChild(modeMenu);

        auto audioMenu = new MenuItem("Audio", NULL);
        audioMenu->setTypeToSelection(System::getIsAudioEnabled() ? 0 : 1, AudioOptions, 2);
		audioMenu->setCallback([](MenuItem *item, bool isManually) -> void {
            System::setIsAudioEnabled(item->selection == 0);
		});
		rootMenu->addChild(audioMenu);


        auto brightnessMenu = new MenuItem("Brightness", NULL);
        brightnessMenu->setTypeToSelection(System::getBrightness(), BrightnessOptions, 5);
		brightnessMenu->setCallback([](MenuItem *item, bool isManually) -> void {
            System::setBrightness(item->selection);
		});
		rootMenu->addChild(brightnessMenu);

		auto deciveAddressMenu = new MenuItem("Address", NULL);
        {
            const auto macAddress = WiFi.macAddress();
            auto size = macAddress.length() + 1;
            char *addressStr = new char[size];
            strcpy(addressStr, macAddress.c_str());
            addressStr[size - 1] = '\0';
            deciveAddressMenu->desc = addressStr;
        }
		rootMenu->addChild(deciveAddressMenu);

		auto versionMenu = new MenuItem("Version", FIRMWARE_VERSION, eNode);
		rootMenu->addChild(versionMenu);
	}

	lastStateMS = millis();
}

void GUI::update(uint32_t ms) {
	char buf[128];
	int32_t x, y;

	if (ms - lastMonitorUpdateMS >= MONITOR_UPDATE_DELAY) {
        sprite.fillScreen(BLACK);

		switch (currentState) {
		case STATE_BOOTING:
            sprite.drawXBitmap(0, 0, LogoXBitmap, NumberXBitmapWidth, NumberXBitmapHeight, WHITE);
			break;

		case STATE_NORMAL:
			{
                auto mode = System::getMode();
                auto status = System::getCurrentCameraStatus();

                if (System::isInTestMode()) {
                    sprite.fillScreen(YELLOW);
                } else {
                    if (mode != MODE_HOST) {
                        if (status == CAMERA_STATUS_PREVIEW) {
                            sprite.fillScreen(GREEN);
                        } else if (status == CAMERA_STATUS_PROGRAM) {
                            sprite.fillScreen(RED);
                        }
                    }
                }

                sprite.drawXBitmap(0, 0, NumberXBitmaps[mode], NumberXBitmapWidth, NumberXBitmapHeight, WHITE);
                sprite.setTextSize(1);
                sprite.setTextColor(WHITE);

                if (mode == MODE_HOST) {
                    char numberStr[2] = { '1', '\0' };
                    auto status = System::getCameraStatus();
                    sprite.setTextSize(3);
                    for (int32_t i = 0; i < CAMERA_COUNT; ++i) {
						x = (i % 4) * 34;
						y = (i / 4) * 44;
                        if (status[i] == CAMERA_STATUS_PREVIEW) {
                            sprite.fillRect(x, y, 34, 43, GREEN);
                        } else if (status[i] == CAMERA_STATUS_PROGRAM) {
                            sprite.fillRect(x, y, 34, 43, RED);
                        } else {
                            sprite.fillRect(x, y, 34, 43, BLACK);
                        }

						numberStr[0] = '1' + i;
                        sprite.drawString(numberStr, 10 + x, y + 10);
                    }
                    
                    for (int32_t i = 0; i < CAMERA_COUNT; ++i) {
                        sprite.drawLine(((i % 4) + 1) * 34, (i / 4) * 44, ((i % 4) + 1) * 34, (i / 4) * 44 + 43, WHITE);
                    }

                    sprite.drawLine(0, 43, 135, 43, WHITE);
					if (CAMERA_COUNT > 4) {
                    	sprite.drawLine(0, 86, 135, 86, WHITE);
					}
                }

                const String& errorMsg = System::getErrorMsg();
                if (errorMsg.length() > 0) {
					sprite.setTextSize(1);
                	sprite.setTextColor(WHITE);
                    sprite.drawString(errorMsg, 8, 225);
                }

			}
			break;

		case STATE_MENU:
			// Heading & Frame
            sprite.setTextSize(2);
            sprite.setTextColor(WHITE);
            sprite.drawString(currentMenu->name, 8, 10);
			sprite.drawLine(0, 30, 135, 30, WHITE);

			int16_t itemCount = isModifyingSelection ? currentMenu->numOptions : currentMenu->numChildren + 1;
			int16_t visibleCount = min(itemCount, currentMenuViewPos + (currentMenu->type == eSelection ? 8 : 5));
			for (uint32_t i = currentMenuViewPos, j = 0; i < visibleCount; ++i, ++j) {
                int16_t lineHeight = (currentMenu->type == eSelection) ? 25 : 38;

				if (currentMenuSelection == i) {
                    sprite.fillRect(0, 36 + j*lineHeight, 135, lineHeight - 1, RED);
				}

                sprite.setTextSize(2);
				if (currentMenu->type == eSelection) {
					sprite.drawString(currentMenu->options[i], 8, 40 + j*lineHeight);
				} else {
					MenuItem *child = currentMenu->children[i-1];
					sprite.drawString(i == 0 ? "<Go back" : child->name, 8, 40 + j*lineHeight);

					if (i != 0) {
						const char *str = NULL;

						if ((child->type == eNode && child->desc != NULL)
							|| (child->type == eSelection)) {
							const char *previewStr = NULL;
							if (child->type == eNode) {
								previewStr = child->desc;
                            } else {
								previewStr = child->options[child->selection];
                            }

							auto descLen = strlen(previewStr);
							if (descLen > 20) {
								int16_t k = 0;
								for (k = 0; k < 20; ++k) {
									buf[k] = previewStr[k];
                                }
								buf[k++] = '.';
								buf[k++] = '.';
								buf[k] = '\0';
								str = buf;
							} else {
								str = previewStr;
                            }
						}

						if (str != NULL) {
                            sprite.setTextSize(1);
							sprite.drawString(str, 8, 60 + j*lineHeight);
						}
					}
				}
			}
			break;
		}

        sprite.pushSprite(0, 0);
		lastMonitorUpdateMS = ms;

	}

	if (ms - lastLogicUpdateMS >= LOGIC_UPDATE_DELAY) {
        auto buttonState = btnA.get();
        if (ms - lastBtnReleasedMs > 4000 && buttonState == ButtonReader::ButtonState::Held) {
            System::powerOff();
        } else if (buttonState == ButtonReader::ButtonState::Open) {
            lastBtnReleasedMs = ms;
        }

		switch (currentState) {
		case STATE_BOOTING:
			if (ms - lastStateMS >= bootingDelay) {
				lastStateMS = ms;
				currentState = STATE_NORMAL;
			}
			break;

		case STATE_NORMAL:
			{
				if (!isLongPressedBefore && buttonState == ButtonReader::ButtonState::Held) {
                    isLongPressedBefore = true;
					currentState = STATE_MENU;
					currentMenu = rootMenu;
					currentMenuSelection = 0;
					currentMenuViewPos = 0;
					lastStateMS = ms;
				} else if (buttonState != ButtonReader::ButtonState::Held) {
                    isLongPressedBefore = false;
                }

                if (System::getMode() == MODE_HOST && buttonState == ButtonReader::ButtonState::Clicked) {
                    System::sendTestMessage();
                }
			}
			break;

		case STATE_MENU:
			{
				MenuItem *selectedItem = NULL;
				if (currentMenuSelection != 0 && !isModifyingSelection) {
					selectedItem = currentMenu->children[currentMenuSelection - 1];
                }

				if (!isLongPressedBefore && buttonState == ButtonReader::ButtonState::Held) {
                    isLongPressedBefore = true;
					if (isModifyingSelection) {
						isModifyingSelection = false;
						currentMenu->selection = currentMenuSelection;
						if (currentMenu->callback) {
							currentMenu->callback(currentMenu, true);
                        }

						currentMenuViewPos = 0;
						currentMenuSelection = currentMenu->parent->getChildIndex(currentMenu)+1;
						currentMenu = currentMenu->parent;
					} else if (currentMenuSelection == 0) {
						if (currentMenu == rootMenu) {
							lastStateMS = ms;
							currentState = STATE_NORMAL;
						} else {
							currentMenu = currentMenu->parent;
							currentMenuSelection = 0;
							currentMenuViewPos = 0;
						}
					} else if (currentMenuSelection > 0) {
						if (selectedItem->type == eSelection) {
							if (selectedItem->isModifiable) {
								isModifyingSelection = true;
								currentMenu = selectedItem;
								currentMenuSelection = selectedItem->selection;
								currentMenuViewPos = 0;
							}
						} else if (selectedItem->type == eNode) {
							if (selectedItem->callback != NULL) {
								selectedItem->callback(selectedItem, true);
                            }

							if (selectedItem->numChildren) {
								currentMenu = selectedItem;
								currentMenuSelection = 0;
								currentMenuViewPos = 0;
							}
						}
						
						int16_t viewDist = currentMenuSelection - currentMenuViewPos;
						int16_t threshold = (currentMenu->type == eSelection ? 7 : 4);
						if (viewDist > threshold) {
							currentMenuViewPos += viewDist - threshold;
						} else if (viewDist < 0) {
							currentMenuViewPos = currentMenuSelection;
						}
					}
				} else {
                    if (buttonState != ButtonReader::ButtonState::Held) {
                        isLongPressedBefore = false;
                    }
                    if (buttonState == ButtonReader::ButtonState::Clicked) {
						int16_t itemCount = isModifyingSelection ?
							currentMenu->numOptions : currentMenu->numChildren + 1;

						if (itemCount > 1) {
							currentMenuSelection += 1;
							while (currentMenuSelection < 0) {
								currentMenuSelection += itemCount;
							}
							while (currentMenuSelection >= itemCount) {
								currentMenuSelection -= itemCount;
							}

							int16_t viewDist = currentMenuSelection - currentMenuViewPos;
							int16_t threshold = (currentMenu->type == eSelection ? 7 : 4);
							if (viewDist > threshold) {
								currentMenuViewPos += viewDist - threshold;
							} else if (viewDist < 0) {
								currentMenuViewPos = currentMenuSelection;
							}
						}
                    }
                }
			}
			break;
		}

		lastLogicUpdateMS = ms;
        btnA.update();
	}
}