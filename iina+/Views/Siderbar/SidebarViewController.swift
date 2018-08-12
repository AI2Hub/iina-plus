//
//  SideBarViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/10.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

enum SidebarItem: String {
    case live
    case bilibili
    case search
    case none
    
    init?(raw: String) {
        self.init(rawValue: raw)
    }
}

class SidebarViewController: NSViewController {

    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var sidebarTableView: NSTableView!
    var sideBarItems: [SidebarItem] = [.live, .search]
    var sideBarSelectedItem: SidebarItem = .none
    override func viewDidLoad() {
        super.viewDidLoad()
        sideBarSelectedItem = sideBarItems.first ?? .none
        NotificationCenter.default.addObserver(forName: .startSearch, object: nil, queue: .main) { _ in
            if let index = self.sideBarItems.index(of: .search) {
                self.sidebarTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .progressStatusChanged, object: nil, queue: .main) {
            if let userInfo = $0.userInfo as? [String: Bool],
                let inProgress = userInfo["inProgress"] {
                if inProgress {
                    self.progressIndicator.startAnimation(nil)
                } else {
                    self.progressIndicator.stopAnimation(nil)
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: .biliStatusChanged, object: nil, queue: .main) {
            if let userInfo = $0.userInfo as? [String: Bool],
                let isLogin = userInfo["isLogin"] {
                self.biliStatusChanged(isLogin)
            }
        }
        Bilibili().isLogin(nil, nil) { re in
            do {
                let _ = try re()
            } catch _ {
                self.biliStatusChanged(false)
            }
        }
        
    }
    
    func biliStatusChanged(_ isLogin: Bool) {
        DispatchQueue.main.async {
            if isLogin {
                if !self.sideBarItems.contains(.bilibili) {
                    self.sideBarItems.insert(.bilibili, at: 1)
                    self.sidebarTableView.insertRows(at: IndexSet(integer: 1), withAnimation: .effectFade)
                } else if self.sideBarItems.count != 3 {
                    self.sideBarItems = [.live, .bilibili, .search]
                    self.sidebarTableView.reloadData()
                }
            } else {
                if let index = self.sideBarItems.firstIndex(of: .bilibili) {
                    self.sideBarItems.remove(at: index)
                    self.sidebarTableView.removeRows(at: IndexSet(integer: index), withAnimation: .effectFade)
                } else if self.sideBarItems.count != 2 {
                    self.sideBarItems = [.live, .search]
                    self.sidebarTableView.reloadData()
                }
            }
        }
    }
    
}

extension SidebarViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return sideBarItems.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let view = sidebarTableView.makeView(withIdentifier: .sidebarTableCellView, owner: self) as? SidebarTableCellView {
            view.item = sideBarItems[row]
            if row == 0 {
                view.isSelected = true
            }
            return view
        }
        return nil
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let row = sideBarItems.index(of: sideBarSelectedItem),
            let view = sidebarTableView.view(atColumn: sidebarTableView.selectedColumn, row: row, makeIfNecessary: false) as? SidebarTableCellView {
            view.isSelected = false
        }
        
        if let view = sidebarTableView.view(atColumn: sidebarTableView.selectedColumn, row: sidebarTableView.selectedRow, makeIfNecessary: false) as? SidebarTableCellView {
            view.isSelected = true
        }
        sideBarSelectedItem = sideBarItems[sidebarTableView.selectedRow]
        
        NotificationCenter.default.post(name: .sideBarSelectionChanged, object: nil, userInfo: ["selectedItem": sideBarSelectedItem.rawValue])
    }
    
    
}
