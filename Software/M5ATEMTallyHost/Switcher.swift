//
//  Switcher.swift
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 06/07/2022.
//

import Foundation
import SwiftUI
import Combine

class Switcher: NSObject, SwitcherDelegate, USBWatcherDelegate {
    private var usbWatcher: USBWatcher!
    private var switcher: SwitcherBase!
    
    @Published var isConnected = false
    @Published var productName = "N/A"
    @Published var inputs: [SwitcherInput] = []
    @Published var previewId: UInt64 = 0
    @Published var programId: UInt64 = 0
    
    override init() {
        super.init()
        
        switcher = SwitcherBase(delegate: self)
        if switcher == nil {
            NSAlert.showPrompt("Could not create Switcher Discovery Instance.\nATEM Software Control may not be installed.")
            NSApplication.shared.terminate(nil)
        }

        usbWatcher = USBWatcher(delegate: self)
    }
    
    func tryToConnect(withUSBDevice device: USBDeviceInfo) {
        if isConnected {
            return
        }
        
        if device.vendorId == 0x1edb && device.classId == 0xef { // Blackmagic Design products
            _ = connectTo(address: "", quiet: true)
        }
    }
    
    func connectTo(address: String = "", quiet: Bool = false) -> Bool {
        let result = switcher.connect(to: address)
        if (result == 0) {
            productName = switcher.getProductName() ?? "N/A"
            inputs = switcher.getInputs()
            previewId = switcher.getPreviewInput()
            programId = switcher.getProgramInput()
            isConnected = true
            return true
        }
        
        if !quiet {
            switch result {
            case 0x63666E72: // bmdSwitcherConnectToFailureNoResponse
                NSAlert.showPrompt("No response from Switcher")
            case 0x63666966: // bmdSwitcherConnectToFailureIncompatibleFirmware
                NSAlert.showPrompt("Switcher has incompatible firmware")
            default:
                NSAlert.showPrompt("Failed to connect: \(result)")
            }
        }
        
        return false;
    }
    
    func switcherDisconnected() {
        isConnected = false
    }
    
    func switcherProgramInputChanged() {
        programId = switcher.getProgramInput()
    }
    
    func switcherPreviewInputChanged() {
        previewId = switcher.getPreviewInput()
    }
    
    func switcherInputLongNameChanged() {
        inputs = switcher.getInputs()
        previewId = switcher.getPreviewInput()
        programId = switcher.getProgramInput()
    }
    
    func usbDeviceAdded(_ device: io_object_t) {
        tryToConnect(withUSBDevice: device.info())
    }
    
    func usbDeviceRemoved(_ device: io_object_t) {
        // Do nothing
    }
}

extension Collection where Element == SwitcherInput {
    var numberOfExternalInput: Int {
        return self.filter({ $0.type == 0x6578746E }).count // bmdSwitcherPortTypeExternal
    }
}
