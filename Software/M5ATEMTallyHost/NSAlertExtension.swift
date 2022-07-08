//
//  NSAlertExtension.swift
//  M5ATEMTallyHost
//
//  Created by UN HON IN on 06/07/2022.
//

import SwiftUI

extension NSAlert {
    typealias PromptResponseClosure = (_ value: String, _ response: NSApplication.ModalResponse) -> Void

    static func showPrompt(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    static func showPromptForReply(
        _ text: String,
        _ buttons: [String] = ["OK", "Cancel"],
        _ completion: PromptResponseClosure) {
        let alert = NSAlert()
        for button in buttons {
            alert.addButton(withTitle:button)
        }
        alert.messageText = text

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = ""
        alert.accessoryView = input
            
        let response = alert.runModal()
        completion(input.stringValue, response)
    }
}
