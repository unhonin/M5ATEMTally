//
//  SwitcherDelegate.h
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 05/07/2022.
//

#ifndef SwitcherDelegate_h
#define SwitcherDelegate_h

#import <Foundation/Foundation.h>

@protocol SwitcherDelegate <NSObject>
@required
- (void)switcherDisconnected;
- (void)switcherProgramInputChanged;
- (void)switcherPreviewInputChanged;
- (void)switcherInputLongNameChanged;

@end

#endif /* SwitcherDelegate_h */
