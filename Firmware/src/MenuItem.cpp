#include "MenuItem.h"

MenuItem::MenuItem(const char *name, const char *desc, MenuType type, MenuItem *parent) {
    this->name = name;
    this->type = type;
    this->parent = parent;
    this->desc = desc;
    this->selection = 0;
    this->numOptions = 0;
    this->numChildren = 0;
    this->callback = NULL;
    this->isModifiable = true;
}

MenuItem::~MenuItem() {
    if (parent != NULL) {
        parent->removeChild(this);
    }
    if (numChildren) {
        while (numChildren) {
            delete children[0];
        }
        delete [] children;
    }
    if (options != NULL) {
        delete [] options;
    }
}

void MenuItem::addChild(MenuItem *item) {
    MenuItem **temp = children;
    children = new MenuItem * [numChildren + 1];

    for(int8_t i = 0; i < numChildren; i++) {
        children[i] = temp[i];
    }

    children[numChildren++] = item;
    if (item->parent) {
        item->parent->removeChild(item);
    }
    item->parent = this;

    if (numChildren > 1) {
        delete [] temp;
    }
}

void MenuItem::removeChild(MenuItem *item) {
    if (numChildren == 1) {
        delete [] children;
        numChildren = 0;
        return;
    }

    MenuItem **temp = children;
    children = new MenuItem *[numChildren - 1];

    for(int8_t i = 0, j = 0; i < numChildren; i++) {
        if (temp[i] != item) {
            children[j++] = temp[i];
        }
    }

    item->parent = NULL;
    delete [] temp;
    numChildren--;
}

bool MenuItem::hasChild(MenuItem *item) {
    for(int8_t i = 0; i < numChildren; i++) {
        if (children[i] == item) {
            return true;
        }
    }

    return false;
}

void MenuItem::setDesc(const char *desc) {
    this->desc = desc;
}

void MenuItem::setTypeToSelection(int8_t selection, const char **options, int8_t numOptions) {
    this->type = eSelection;
    this->selection = selection;
    this->options = options;
    this->numOptions = numOptions;

    if (numOptions > 0) {
        this->options = new const char * [numOptions];
        for(int8_t i = 0; i < numOptions; i++) {
            this->options[i] = options[i];
        }
    }
}

void MenuItem::addOption(const char *option) {
    const char **temp = options;
    options = new const char *[numOptions + 1];

    for(int8_t i = 0; i < numOptions; i++) {
        options[i] = temp[i];
    }

    options[numOptions++] = option;
    if (numOptions > 1) {
        delete [] temp;
    }
}

void MenuItem::setCallback(const MenuCallback& callback) {
    this->callback = callback;
}

int8_t MenuItem::getChildIndex(MenuItem *item) {
    for(int8_t i = 0; i < numChildren; i++) {
        if (children[i] == item) {
            return i;
        }
    }

    return -1;
}