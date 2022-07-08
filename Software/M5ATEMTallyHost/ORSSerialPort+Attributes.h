//
//  ORSSerialPort+Attributes.h
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 06/07/2022.
//

#ifndef ORSSerialPort_Attributes_h
#define ORSSerialPort_Attributes_h

#import <ORSSerialPort.h>

@interface ORSSerialPort (Attributes)

@property (nonatomic, readonly) NSDictionary *ioDeviceAttributes;
@property (nonatomic, readonly) NSNumber *vendorID;
@property (nonatomic, readonly) NSNumber *productID;

@end

#endif /* ORSSerialPort_Attributes_h */
