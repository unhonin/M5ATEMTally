//
//  AppDelegate.swift
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 06/07/2022.
//

import Cocoa
import SwiftUI
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var switcher: Switcher!
    var transmitter: Transmitter!
    
    var statusItem: NSStatusItem!
    var transmitterStatusItem: NSMenuItem!
    var transmitterSendTestItem: NSMenuItem!
    var switcherStatusItem: NSMenuItem!
    var switcherNameItem: NSMenuItem!
    var switcherExtInputsItem: NSMenuItem!
    var switcherPreviewItem: NSMenuItem!
    var switcherProgramItem: NSMenuItem!
    var switcherConnectItem: NSMenuItem!
    
    var cancellables: Set<AnyCancellable> = []
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "StatusBarIcon")
            button.imagePosition = .imageLeft
        }
        
        switcher = Switcher()
        transmitter = Transmitter(switcher: switcher)
        
        setupMenus()
    }
    
    func setupMenus() {
        let menu = NSMenu()

        let transmitterItem = NSMenuItem()
        transmitterItem.attributedTitle = NSAttributedString(string: "Transmitter", attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 15)])
        transmitterItem.isEnabled = false
        menu.addItem(transmitterItem)
        
        transmitterStatusItem = NSMenuItem()
        menu.addItem(transmitterStatusItem)
        
        transmitterSendTestItem = NSMenuItem(title: "Send test command", action: #selector(transmitterSendTestPressed), keyEquivalent: "t")
        menu.addItem(transmitterSendTestItem)

        menu.addItem(NSMenuItem.separator())

        let switcherItem = NSMenuItem()
        switcherItem.attributedTitle = NSAttributedString(string: "Switcher", attributes: [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 15)])
        menu.addItem(switcherItem)
        
        switcherStatusItem = NSMenuItem()
        menu.addItem(switcherStatusItem)
        
        switcherNameItem = NSMenuItem()
        menu.addItem(switcherNameItem)
        
        switcherExtInputsItem = NSMenuItem()
        menu.addItem(switcherExtInputsItem)

        switcherPreviewItem = NSMenuItem()
        menu.addItem(switcherPreviewItem!)
        
        switcherProgramItem = NSMenuItem()
        menu.addItem(switcherProgramItem)
        
        switcherConnectItem = NSMenuItem(title: "Connect to..", action: #selector(switcherConnectPressed), keyEquivalent: "2")
        menu.addItem(switcherConnectItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Assign the menu
        statusItem?.menu = menu
        
        // Hook for status changes
        Publishers.CombineLatest(switcher.$isConnected, transmitter.$isConnected)
            .sink {
                let running = ($0 && $1)
                self.statusItem?.button?.attributedTitle =
                    NSAttributedString(
                        string: running ? "Running" : "Stopped",
                        attributes: [NSAttributedString.Key.foregroundColor : running ? NSColor.green : NSColor.red])
            }
            .store(in: &cancellables)
        
        transmitter.$isConnected.sink { value in
            self.transmitterStatusItem.title = "Status: \(value ? "Connected" : "Disconnected")"
        }
        .store(in: &cancellables)
        
        switcher.$isConnected.sink { value in
            self.switcherConnectItem.isHidden = value
            self.switcherStatusItem.title = "Status: \(value ? "Connected" : "Disconnected")"
            self.switcherNameItem.title = "Device: \(self.switcher.productName)"
        }
        .store(in: &cancellables)
        
        switcher.$inputs.sink {
            self.switcherExtInputsItem.title = "External Inputs: \($0.numberOfExternalInput)"
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest3(switcher.$isConnected, switcher.$inputs, switcher.$previewId)
            .sink { connected, inputs, id in
                var previewName = "N/A"
                if connected == true, let name = inputs.first(where: { $0.id == id })?.name {
                    previewName = name
                }
                self.switcherPreviewItem.title = "Preview: \(previewName)"
            }
            .store(in: &cancellables)
        
        Publishers.CombineLatest3(switcher.$isConnected, switcher.$inputs, switcher.$programId)
            .sink { connected, inputs, id in
                var programName = "N/A"
                if connected == true, let name = inputs.first(where: { $0.id == id })?.name {
                    programName = name
                }
                self.switcherProgramItem.title = "Program: \(programName)"
            }
            .store(in: &cancellables)
    }
    
    @objc func transmitterSendTestPressed() {
        transmitter.sendTestCommand()
    }
    
    @objc func switcherConnectPressed() {
        NSAlert.showPromptForReply(
            "Enter the IP address you want to connect\nLeave blank if you want to connect with USB",
            ["Connect", "Cancel"])
        { [weak self] value, response in
            guard response == .alertFirstButtonReturn,
                  let self = self,
                  !self.switcher.isConnected else {
                return
            }
            
            _ = self.switcher.connectTo(address: value)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

