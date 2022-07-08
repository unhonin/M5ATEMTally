//
//  SwitcherBase.h
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 05/07/2022.
//

#ifndef Switcher_h
#define Switcher_h

#import "BMDSwitcherAPI.h"
#import "SwitcherDelegate.h"

@interface SwitcherInput : NSObject
@property NSString *_Nullable name;
@property UInt64 id;
@property UInt32 type;
@end

@interface SwitcherBase : NSObject

- (SwitcherBase * _Nullable)initWithDelegate:(NSObject<SwitcherDelegate> *_Nonnull)delegate;

- (NSInteger)connectTo:(NSString *_Nonnull)address;

- (NSString *_Nullable)getProductName;

- (UInt64)getProgramInput;

- (UInt64)getPreviewInput;

- (NSArray<SwitcherInput *> *_Nonnull)getInputs;

- (void)onDisconnected;

@end

#endif /* SwitcherDiscovery_h */
