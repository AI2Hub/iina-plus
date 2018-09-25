//
//  WaitingTableCellView.swift
//  iina+
//
//  Created by xjbeta on 2018/7/13.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class WaitingTableCellView: NSTableCellView {

    @IBOutlet weak var waitProgressIndicator: NSProgressIndicator!
    @IBOutlet weak var errorInfoTextField: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
    }
    enum Status {
        case waiting, error
    }
    
    func setStatus(_ status: Status) {
        switch status {
        case .waiting:
            waitProgressIndicator.startAnimation(nil)
            waitProgressIndicator.isHidden = false
            errorInfoTextField.isHidden = true
        case .error:
            waitProgressIndicator.isHidden = true
            errorInfoTextField.isHidden = false
        }
    }
    
}
