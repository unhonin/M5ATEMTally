//
//  USBWatcher.swift
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 06/07/2022.
//

import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib
import IOKit.serial


public class USBDeviceInfo {
    let name: String
    let vendorId: UInt16
    let productId: UInt16
    let classId: UInt8
    let subclassId: UInt8
    let bsdPath: String
    
    init(name: String, vendorId: UInt16, productId: UInt16, classId: UInt8, subclassId: UInt8, bsdPath: String) {
        self.name = name
        self.vendorId = vendorId
        self.productId = productId
        self.classId = classId
        self.subclassId = subclassId
        self.bsdPath = bsdPath
    }
    
    func toString() -> String {
        return String(format: "Name: %@, Vendor: %04x, Product: %04x, Class: %02x, Subclass: %02x, bsdPath: %@", name, vendorId, productId, classId, subclassId, bsdPath)
    }
}

public protocol USBWatcherDelegate {
    /// Called on the main thread when a device is connected.
    func usbDeviceAdded(_ device: io_object_t)

    /// Called on the main thread when a device is disconnected.
    func usbDeviceRemoved(_ device: io_object_t)
}

/// An object which observes USB devices added and removed from the system.
/// Abstracts away most of the ugliness of IOKit APIs.
public class USBWatcher {
    private var delegate: USBWatcherDelegate?
    private let notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public init(delegate: USBWatcherDelegate) {
        self.delegate = delegate

        func handleNotification(instance: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
            let watcher = Unmanaged<USBWatcher>.fromOpaque(instance!).takeUnretainedValue()
            let handler: ((io_iterator_t) -> Void)?
            switch iterator {
            case watcher.addedIterator: handler = watcher.delegate?.usbDeviceAdded
            case watcher.removedIterator: handler = watcher.delegate?.usbDeviceRemoved
            default: assertionFailure("received unexpected IOIterator"); return
            }
            while case let device = IOIteratorNext(iterator), device != IO_OBJECT_NULL {
                handler?(device)
                IOObjectRelease(device)
            }
        }
        //kIOSerialBSDServiceValue
        let query = IOServiceMatching(kIOUSBDeviceClassName)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        // Watch for connected devices.
        IOServiceAddMatchingNotification(
            notificationPort, kIOMatchedNotification, query,
            handleNotification, opaqueSelf, &addedIterator)

        handleNotification(instance: opaqueSelf, addedIterator)

        // Watch for disconnected devices.
        IOServiceAddMatchingNotification(
            notificationPort, kIOTerminatedNotification, query,
            handleNotification, opaqueSelf, &removedIterator)

        handleNotification(instance: opaqueSelf, removedIterator)

        // Add the notification to the main run loop to receive future updates.
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue(),
            .commonModes)
    }
    
    static func listAllDevices() -> [USBDeviceInfo] {
        var iter: io_iterator_t = 0
        var device: io_service_t = 0
        
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &iter) != KERN_SUCCESS {
            return []
        }
        
        var infos: [USBDeviceInfo] = []
        
        device = IOIteratorNext(iter)
        while device != 0 {
            infos.append(device.info())

            IOObjectRelease(device)
            device = IOIteratorNext(iter)
        }

        IOObjectRelease(iter)
        return infos
    }

    deinit {
        IOObjectRelease(addedIterator)
        IOObjectRelease(removedIterator)
        IONotificationPortDestroy(notificationPort)
    }
}

extension io_object_t {
    /// - Returns: The device's name.
    func info() -> USBDeviceInfo {
        var deviceNameCString = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        let deviceNameResult = IORegistryEntryGetName(self, &deviceNameCString)
        let deviceName = (deviceNameResult == kIOReturnSuccess) ? String(cString: &deviceNameCString) : "N/A"

        // Get plug-in interface for current USB device
        var plugInInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let plugInInterfaceResult = IOCreatePlugInInterfaceForService(
            self,
            kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugInInterfacePtrPtr,
            &score)
        
        // Dereference pointer for the plug-in interface
        guard plugInInterfaceResult == kIOReturnSuccess,
            let plugInInterface = plugInInterfacePtrPtr?.pointee?.pointee else {
            print("Unable to get Plug-In Interface")
            return USBDeviceInfo(
                name: deviceName,
                vendorId: 0,
                productId: 0,
                classId: 0,
                subclassId: 0,
                bsdPath: "")
        }

        // Use plug-in interface to get a device interface.
        var deviceInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?
        let deviceInterfaceResult = withUnsafeMutablePointer(to: &deviceInterfacePtrPtr) {
            $0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
                plugInInterface.QueryInterface(
                    plugInInterfacePtrPtr,
                    CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                    $0)
            }
        }

        // Plug-in interface is no longer needed.
        _ = plugInInterface.Release(plugInInterfacePtrPtr)
        
        var vendorId: UInt16 = 0
        var productId: UInt16 = 0
        var classId: UInt8 = 0
        var subclassId: UInt8 = 0
        var bsdPath = ""

        // Dereference pointer for the device interface.
        if deviceInterfaceResult == kIOReturnSuccess,
           let deviceInterface = deviceInterfacePtrPtr?.pointee?.pointee {
            _ = deviceInterface.GetDeviceVendor(deviceInterfacePtrPtr, &vendorId)
            _ = deviceInterface.GetDeviceProduct(deviceInterfacePtrPtr, &productId)
            _ = deviceInterface.GetDeviceClass(deviceInterfacePtrPtr, &classId)
            _ = deviceInterface.GetDeviceSubClass(deviceInterfacePtrPtr, &subclassId)

            // Device interface is no longer needed:
            _ = deviceInterface.Release(deviceInterfacePtrPtr)
        }
        
        var properties: Unmanaged<CFMutableDictionary>? = nil
        if IORegistryEntryCreateCFProperties(
            self as io_registry_entry_t,
            &properties,
            kCFAllocatorDefault, 0) == kIOReturnSuccess {
            if let deviceBSDName_cf = IORegistryEntrySearchCFProperty(
                self,
                kIOServicePlane,
                "IOCalloutDevice" as CFString,
                kCFAllocatorDefault,
                UInt32(kIORegistryIterateRecursively )) {
                bsdPath = "\(deviceBSDName_cf)"
            }
        }
        
        return USBDeviceInfo(
            name: deviceName,
            vendorId: vendorId,
            productId: productId,
            classId: classId,
            subclassId: subclassId,
            bsdPath: bsdPath)
    }
}

//
// These constants are not imported into Swift from IOUSBLib.h as they
// are all #define constants
//

fileprivate let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault,
                                                                  0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
                                                                  0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

fileprivate let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault,
                                                            0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
                                                            0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

fileprivate let kIOUSBDeviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault,
                                                             0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
                                                             0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
