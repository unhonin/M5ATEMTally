//
//  Transmitter.swift
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 06/07/2022.
//

import Foundation
import ORSSerial
import Combine
import AppKit

class Transmitter : NSObject, ORSSerialPortDelegate {
    private let switcher: Switcher
    private var port: ORSSerialPort?
    private var dataReceived: [UInt8] = []
    private var pingTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    
    @Published var isConnected = false
    
    init(switcher: Switcher) {
        self.switcher = switcher
        super.init()
        
        Publishers.CombineLatest(switcher.$previewId, switcher.$programId)
            .sink { previewId, programId in
                self.sendStatus(previewId, programId)
            }
            .store(in: &cancellables)
        
        // Scan all attached serial devices
        for atachedPort in ORSSerialPortManager.shared().availablePorts {
            if tryToConnect(withPort: atachedPort) {
                break
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDeviceAttached),
            name: NSNotification.Name.ORSSerialPortsWereConnected,
            object: nil)
    }
    
    @objc func onDeviceAttached(notification: NSNotification) {
        if let connectedPorts = notification.userInfo?[ORSConnectedSerialPortsKey] as? Array<ORSSerialPort> {
            for item in connectedPorts {
                if tryToConnect(withPort: item) {
                    break
                }
            }
        }
    }
    
    func tryToConnect(withPort targetPort: ORSSerialPort) -> Bool {
        if port == nil &&
            !isConnected &&
            targetPort.vendorID == 0x0403 &&
            targetPort.productID == 0x6001 {
            port = targetPort
            port!.delegate = self
            port!.baudRate = 115200
            port!.open()
            return true
        }
        
        return false
    }
    
    func sendTestCommand() {
        send([MessageType.test, 0xFF])
    }
    
    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        port = nil
        isConnected = false
    }
    
    func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        port = nil
        isConnected = false
    }
    
    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        send([MessageType.ping])
        pingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            self.pingTimer = nil
            if self.isConnected == false && self.port != nil {
                self.port = nil
                NSAlert.showPrompt("Failed to connect to transmitter! No respond from the device")
            }
        }
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        port = nil
        isConnected = false
        print("Transmitter error encounted: \(error)")
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        dataReceived.append(contentsOf: data)
        var i = 0
        while i < dataReceived.count {
            if dataReceived[i] == 0x0A { // '\n'
                if let packet = String(data: Data(dataReceived[0..<i]), encoding: .ascii)?.hexadecimal {
                    processPacket([UInt8](packet))
                }
                dataReceived.removeSubrange(0...i)
                i = 0
                continue
            }
            i += 1
        }
        
        if dataReceived.count > 20 {
            dataReceived.removeAll()
        }
    }
    
    func processPacket(_ data: [UInt8]) {
        if data.count < 4 {
            print("Invaild packet length:\(data.count)")
            return
        }
        
        if !validifyCRC(for: data[...]) || data[0] != UInt8(data.count) {
            print("Invaild packet received: \(data)")
            return
        }
        
        switch data[1] {
        case MessageType.pong:
            if isConnected == false && port != nil {
                pingTimer?.invalidate()
                pingTimer = nil
                isConnected = true
                sendStatus()
            }
            break;
            
        case MessageType.error:
            print("Error message received from transmitter")
            break
            
        default:
            break
        }
    }
    
    private func sendStatus(_ previewId: UInt64? = nil, _ programId: UInt64? = nil) {
        let count = switcher.inputs.numberOfExternalInput
        if count == 0 {
            return
        }
        
        var previewId = previewId
        if previewId == nil {
            previewId = switcher.previewId
        }
        
        var programId = programId
        if programId == nil {
            programId = switcher.programId
        }
        
        var packet: [UInt8] = [MessageType.status, UInt8(count)]
        for i in 1...count {
            if i == programId! {
                packet.append(CameraStatus.program)
            } else if i == previewId! {
                packet.append(CameraStatus.preview)
            } else {
                packet.append(CameraStatus.standby)
            }
        }
        send(packet)
    }
    
    private func send(_ data: [UInt8]) {
        guard let port = port else {
            return
        }
        
        var bytes: [UInt8] = []
        bytes.append(UInt8(data.count + 3))
        bytes.append(contentsOf: data)
        
        let crc = calculateCRC(for: bytes[...])
        bytes.append(UInt8(crc & 0xFF))
        bytes.append(UInt8((crc >> 8) & 0xFF))
        
        let str = "\(Data(bytes).hexEncodedString())\n"
        if !port.send(str.data(using: .ascii)!) {
            print("Failed to send data to transmitter")
        }
    }

    private func calculateCRC(for data: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0
        for i in 0..<data.count {
            crc ^= UInt16(data[i]) << 8
            for _ in 0..<8 {
                if ((crc & (1 << 15)) != 0) {
                  crc <<= 1
                  crc ^= 0x8001
                } else {
                  crc <<= 1
                }
            }
        }
        return crc
    }
    
    private func validifyCRC(for data: ArraySlice<UInt8>) -> Bool {
        let length = data.count
        let crc = calculateCRC(for: data[0..<length-2])
        return crc == (UInt16(data[length-2]) | (UInt16(data[length-1]) << 8))
    }
}

fileprivate class MessageType {
    static let test        : UInt8 = 0x01
    static let status      : UInt8 = 0x02
    static let ping        : UInt8 = 0x03
    static let pong        : UInt8 = 0x04

    static let ok          : UInt8 = 0x00
    static let error       : UInt8 = 0xFF
}


fileprivate class CameraStatus {
    static let standby     : UInt8 = 0
    static let preview     : UInt8 = 1
    static let program     : UInt8 = 2
}
