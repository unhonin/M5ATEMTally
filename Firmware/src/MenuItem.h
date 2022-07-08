#ifndef _MENUITEM_HH
#define _MENUITEM_HH

#include <M5StickCPlus.h>
#include <functional>

enum MenuType
{
    eNode = 0,
    //eNumber = 1,
    eSelection = 2
};

class MenuItem;
typedef std::function<void (MenuItem *item, bool isManually)> MenuCallback;

class MenuItem
{
public:
    const char *name;
    const char *desc;
    MenuType type;
    MenuCallback callback;

    const char **options;
    int8_t numOptions;
    int8_t selection;

    MenuItem *parent;
    MenuItem **children;
    uint8_t numChildren;

    uint32_t userData;
    bool isModifiable;

    MenuItem(const char *name, const char *desc = NULL, MenuType type = eNode, MenuItem *parent = NULL);

    ~MenuItem();

    void addChild(MenuItem *item);

    void removeChild(MenuItem *item);

    bool hasChild(MenuItem *item);

    void setDesc(const char *desc);

    void setTypeToSelection(int8_t selection, const char **options = NULL, int8_t numOptions = 0);

    void addOption(const char *option);

    void setCallback(const MenuCallback& callback);

    int8_t getChildIndex(MenuItem *item);
};

#endif