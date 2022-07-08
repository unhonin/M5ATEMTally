//
//  SwitcherBase.m
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 05/07/2022.
//

#import <Foundation/Foundation.h>
#import <list>
#import "SwitcherBase.h"

#include <atomic>
#include <string>

static inline bool operator== (const REFIID& iid1, const REFIID& iid2) {
    return CFEqual(&iid1, &iid2);
}

class MixEffectBlockMonitor : public IBMDSwitcherMixEffectBlockCallback {
public:
    MixEffectBlockMonitor(NSObject<SwitcherDelegate> *_delegate) : delegate(_delegate), refCount(1) {}

protected:
    virtual ~MixEffectBlockMonitor() {}

public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv) {
        if (!ppv) {
            return E_POINTER;
        }
        
        if (iid == IID_IBMDSwitcherCallback) {
            *ppv = static_cast<IBMDSwitcherMixEffectBlockCallback*>(this);
            AddRef();
            return S_OK;
        }
        
        if (CFEqual(&iid, IUnknownUUID)) {
            *ppv = static_cast<IUnknown*>(this);
            AddRef();
            return S_OK;
        }
        
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef(void) {
        return std::atomic_fetch_add(&refCount, 1);
    }

    ULONG STDMETHODCALLTYPE Release(void) {
        int newCount = std::atomic_fetch_add(&refCount, -1);
        if (newCount == 0) {
            delete this;
        }
        return newCount;
    }
    
    HRESULT Notify(BMDSwitcherMixEffectBlockEventType eventType) {
        switch (eventType) {
            case bmdSwitcherMixEffectBlockEventTypeProgramInputChanged:
                [delegate performSelectorOnMainThread:@selector(switcherProgramInputChanged) withObject:nil waitUntilDone:YES];
                break;
            case bmdSwitcherMixEffectBlockEventTypePreviewInputChanged:
                [delegate performSelectorOnMainThread:@selector(switcherPreviewInputChanged) withObject:nil waitUntilDone:YES];
                break;
            default:
                break;
        }
        return S_OK;
    }

private:
    NSObject<SwitcherDelegate> *delegate;
    std::atomic<int> refCount;
};

class InputMonitor : public IBMDSwitcherInputCallback {
public:
    InputMonitor(IBMDSwitcherInput* _input, NSObject<SwitcherDelegate> *_delegate) : input(_input), delegate(_delegate), refCount(1) {
        input->AddRef();
        input->AddCallback(this);
    }

protected:
    ~InputMonitor() {
        input->RemoveCallback(this);
        input->Release();
    }
    
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv) {
        if (!ppv) {
            return E_POINTER;
        }
        
        if (iid == IID_IBMDSwitcherCallback) {
            *ppv = static_cast<IBMDSwitcherInputCallback*>(this);
            AddRef();
            return S_OK;
        }
        
        if (CFEqual(&iid, IUnknownUUID)) {
            *ppv = static_cast<IUnknown*>(this);
            AddRef();
            return S_OK;
        }
        
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef(void) {
        return std::atomic_fetch_add(&refCount, 1);
    }

    ULONG STDMETHODCALLTYPE Release(void) {
        int newCount = std::atomic_fetch_add(&refCount, -1);
        if (newCount == 0) {
            delete this;
        }
        return newCount;
    }

    HRESULT Notify(BMDSwitcherInputEventType eventType) {
        switch (eventType) {
            case bmdSwitcherInputEventTypeLongNameChanged:
                [delegate performSelectorOnMainThread:@selector(switcherInputLongNameChanged) withObject:nil waitUntilDone:YES];
                break;
            default:
                break;
        }
        
        return S_OK;
    }
    
private:
    IBMDSwitcherInput* input;
    NSObject<SwitcherDelegate> *delegate;
    std::atomic<int> refCount;
};

class SwitcherMonitor : public IBMDSwitcherCallback {
public:
    SwitcherMonitor(SwitcherBase *_switcher, NSObject<SwitcherDelegate> *_delegate) : switcher(_switcher), delegate(_delegate), refCount(1) {}

protected:
    virtual ~SwitcherMonitor() { }
    
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv) {
        if (!ppv) {
            return E_POINTER;
        }
        
        if (iid == IID_IBMDSwitcherCallback) {
            *ppv = static_cast<IBMDSwitcherCallback*>(this);
            AddRef();
            return S_OK;
        }
        
        if (CFEqual(&iid, IUnknownUUID)) {
            *ppv = static_cast<IUnknown*>(this);
            AddRef();
            return S_OK;
        }
        
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef(void) {
        return std::atomic_fetch_add(&refCount, 1);
    }

    ULONG STDMETHODCALLTYPE Release(void) {
        int newCount = std::atomic_fetch_add(&refCount, -1);
        if (newCount == 0) {
            delete this;
        }
        return newCount;
    }
    
    HRESULT STDMETHODCALLTYPE Notify(BMDSwitcherEventType eventType, BMDSwitcherVideoMode coreVideoMode) {
        if (eventType == bmdSwitcherEventTypeDisconnected) {
            [switcher performSelectorOnMainThread:@selector(onDisconnected) withObject:nil waitUntilDone:YES];
            [delegate performSelectorOnMainThread:@selector(switcherDisconnected) withObject:nil waitUntilDone:YES];
        }
        return S_OK;
    }
    
private:
    SwitcherBase *switcher;
    NSObject<SwitcherDelegate> *delegate;
    std::atomic<int> refCount;
};

@implementation SwitcherInput

@end

@implementation SwitcherBase {
    IBMDSwitcherDiscovery *discovery;
    IBMDSwitcher *switcher;
    SwitcherMonitor* switcherMonitor;
    IBMDSwitcherMixEffectBlock* mixEffectBlock;
    MixEffectBlockMonitor* mixEffectBlockMonitor;
    std::list<InputMonitor*> inputMonitors;
    
    NSObject<SwitcherDelegate> *delegate;
}

- (SwitcherBase *)initWithDelegate:(NSObject<SwitcherDelegate> *)delegate {
    SwitcherBase *instance = [SwitcherBase alloc];
    instance->discovery = CreateBMDSwitcherDiscoveryInstance();
    if (!instance->discovery) {
        return NULL;
    }
    
    instance->switcher = NULL;
    instance->switcherMonitor = new SwitcherMonitor(self, delegate);
    instance->mixEffectBlock = NULL;
    instance->mixEffectBlockMonitor = new MixEffectBlockMonitor(delegate);
    instance->delegate = delegate;
    return instance;
}

- (void)dealloc {
    [self onDisconnected];
    
    if (switcherMonitor != NULL) {
        switcherMonitor->Release();
        switcherMonitor = NULL;
    }
    
    if (mixEffectBlockMonitor != NULL) {
        mixEffectBlockMonitor->Release();
        mixEffectBlockMonitor = NULL;
    }
}

- (void)onDisconnected {
    for (std::list<InputMonitor*>::iterator it = inputMonitors.begin(); it != inputMonitors.end(); ++it) {
        (*it)->Release();
    }
    inputMonitors.clear();
    
    if (mixEffectBlock != NULL) {
        if (mixEffectBlockMonitor != NULL) {
            mixEffectBlock->RemoveCallback(mixEffectBlockMonitor);
        }
        mixEffectBlock->Release();
        mixEffectBlock = NULL;
    }
    
    if (switcher) {
        if (switcherMonitor != NULL) {
            switcher->RemoveCallback(switcherMonitor);
        }
        switcher->Release();
        switcher = NULL;
    }
}

- (NSInteger)connectTo:(NSString *)address {
    [self onDisconnected];
    
    BMDSwitcherConnectToFailure failReason;
    HRESULT hr = discovery->ConnectTo((__bridge CFStringRef)address, &switcher, &failReason);
    if (!SUCCEEDED(hr)) {
        return (NSInteger)failReason;
    }
    
    switcher->AddCallback(switcherMonitor);

    // Create an InputMonitor for each input so we can catch any changes to input names
    IBMDSwitcherInputIterator* inputIterator = NULL;
    hr = switcher->CreateIterator(IID_IBMDSwitcherInputIterator, (void**)&inputIterator);
    if (SUCCEEDED(hr)) {
        IBMDSwitcherInput* input = NULL;
        
        // For every input, install a callback to monitor property changes on the input
        while (S_OK == inputIterator->Next(&input)) {
            InputMonitor* inputMonitor = new InputMonitor(input, delegate);
            input->Release();
            inputMonitors.push_back(inputMonitor);
        }
        inputIterator->Release();
        inputIterator = NULL;
    }
    
    // Get the mix effect block iterator
    IBMDSwitcherMixEffectBlockIterator* iterator = NULL;
    hr = switcher->CreateIterator(IID_IBMDSwitcherMixEffectBlockIterator, (void**)&iterator);
    if (FAILED(hr)) {
        NSLog(@"Could not create IBMDSwitcherMixEffectBlockIterator iterator");
        iterator->Release();
        return -1;
    }
    
    // Use the first Mix Effect Block
    if (S_OK != iterator->Next(&mixEffectBlock)) {
        NSLog(@"Could not get the first IBMDSwitcherMixEffectBlock");
        iterator->Release();
        return -1;
    }
    
    mixEffectBlock->AddCallback(mixEffectBlockMonitor);
    iterator->Release();
    return 0;
}

- (NSString *)getProductName {
    CFStringRef nameRef;
    if (FAILED(switcher->GetProductName(&nameRef))) {
        return NULL;
    }
    return (__bridge_transfer NSString *)nameRef;
}

- (UInt64)getProgramInput {
    BMDSwitcherInputId programId;
    mixEffectBlock->GetProgramInput(&programId);
    return programId;
}

- (UInt64)getPreviewInput {
    BMDSwitcherInputId previewId;
    mixEffectBlock->GetPreviewInput(&previewId);
    return previewId;
}

- (NSArray<SwitcherInput *> *)getInputs {
    HRESULT result;
    IBMDSwitcherInputIterator* inputIterator = NULL;
    IBMDSwitcherInput* input = NULL;
    
    result = switcher->CreateIterator(IID_IBMDSwitcherInputIterator, (void**)&inputIterator);
    if (FAILED(result)) {
        NSLog(@"Could not create IBMDSwitcherInputIterator iterator");
        return NULL;
    }
    
    NSMutableArray<SwitcherInput *> *inputs = [NSMutableArray<SwitcherInput *> array];
    
    while (S_OK == inputIterator->Next(&input)) {
        CFStringRef name;
        BMDSwitcherInputId id;
        BMDSwitcherPortType type;

        input->GetInputId(&id);
        input->GetLongName(&name);
        input->GetPortType(&type);
        input->Release();
        
        SwitcherInput *inputInfo = [SwitcherInput alloc];
        inputInfo.name = (__bridge_transfer NSString *)name;
        inputInfo.type = type;
        inputInfo.id = id;
        [inputs addObject:inputInfo];
    }
    inputIterator->Release();
    
    return inputs;
}

@end
