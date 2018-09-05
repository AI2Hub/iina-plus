//
//  DanmakuWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/31.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal
import SocketRocket

class DanmakuWindowController: NSWindowController, NSWindowDelegate {

    var targeTitle = ""
    var videoUrl = ""
    var waittingSocket = false
    
    let biliLiveServer = URL(string: "wss://broadcastlv.chat.bilibili.com/sub")
    var biliLiveRoomID = 0
    var socket: SRWebSocket? = nil
    var liveSite: LiveSupportList = .unsupported
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.setFrame((NSScreen.main?.frame)!, display: false)
        
        window?.level = NSWindow.Level(rawValue: Int(kCGStatusWindowLevel))
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.ignoresMouseEvents = true
        window?.orderOut(self)
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(foremostAppActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        
    }
    
    func initDanmakuForBilibili(_ title: String, url: String) {
        targeTitle = title
        videoUrl = url
        waittingSocket = true
        if let url = URL(string: url),
            let aid = Int(url.lastPathComponent.replacingOccurrences(of: "av", with: "")) {
            var cid = 0
            
            let group = DispatchGroup()
            group.enter()
            Bilibili().getVideoList(aid, { vInfo in
                if vInfo.count == 1 {
                    cid = vInfo[0].cid
                } else if let p = url.query?.replacingOccurrences(of: "p=", with: ""),
                    var pInt = Int(p) {
                    pInt -= 1
                    if pInt < vInfo.count,
                        pInt >= 0 {
                    cid = vInfo[pInt].cid
                    }
                }
                group.leave()
            }) { re in
                do {
                    let _ = try re()
                } catch let error {
                    Logger.log("Get cid for danmamu error: \(error)")
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                guard cid != 0 else { return }
                
                HTTP.GET("https://comment.bilibili.com/\(cid).xml") {
                    self.loadDM($0.data)
                }
            }
        }
    }
    
    func initDanmakuForBiliLive(_ title: String, url: String) {
        liveSite = .bilibili
        targeTitle = title
        videoUrl = url
        waittingSocket = true
        
        socket = SRWebSocket(url: biliLiveServer!)
        socket?.delegate = self
        
        let roomID = URL(string: url)?.lastPathComponent ?? ""
        
        HTTP.GET("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)") {
            do {
                let json = try JSONParser.JSONObjectWithData($0.data)
                self.biliLiveRoomID = try json.value(for: "data.room_id")
                self.socket?.open()
                if let danmakuViewController = self.contentViewController as? DanmakuViewController {
                    DispatchQueue.main.async {
                        danmakuViewController.webView.evaluateJavaScript("window.initDM();") { (_, _) in
                        }
                    }
                }
            } catch let error {
                Logger.log("can't find bilibili live room id \(error)")
            }
        }
    }
    
    private var timer: DispatchSourceTimer?
    
    private var timerQueue = DispatchQueue(label: "com.xjbeta.iina+.WebSocketKeepLive")
    
    private func startTimer() {
        timer = DispatchSource.makeTimerSource(flags: [], queue: timerQueue)
        if let timer = timer {
            timer.schedule(deadline: .now(), repeating: .seconds(30))
            timer.setEventHandler {
                try? self.socket?.send(data: self.pack(format: "NnnNN", values: [16, 16, 1, 2, 1]) as Data)
            }
            timer.resume()
        }
    }
    
    
    
    func initMpvSocket() {
        Processes.shared.mpvSocket { socketStr in
            var isPasued = false
            if let webView = (self.contentViewController as? DanmakuViewController)?.webView {
                DispatchQueue.main.async {
                    do {
                        let data = socketStr.data(using: .utf8) ?? Data()
                        let json = try JSONParser.JSONObjectWithData(data)
                        let socketEvent = try MpvSocketEvent(object: json)
                        if let event = socketEvent.event {
                            switch event {
                            case .pause:
                                webView.evaluateJavaScript("window.cm.stop()") { (_, _) in
                                }
                                isPasued = true
                                Logger.log("iina pasued")
                            case .unpause:
                                webView.evaluateJavaScript("window.cm.start()") { (_, _) in
                                }
                                isPasued = false
                                Logger.log("iina unpause")
                            case .propertyChange:
                                if socketEvent.name == "time-pos" {
                                    guard let timeStr = socketEvent.data, let time = Double(timeStr), !isPasued else {
                                        return
                                    }
                                    webView.evaluateJavaScript("window.cm.time(Math.floor(\(time * 1000)))") { (_, _) in
                                    }
//                                    Logger.log("iina seek")
                                } else if socketEvent.name == "window-scale" {
                                    self.resizeWindow()
                                    webView.evaluateJavaScript("window.resize()") { (_, _) in
                                    }
                                    Logger.log("iina window-scale")
                                }
                            case .idle:
                                self.window?.orderOut(self)
                                Logger.log("iina idle")
                            }
                        } else if let re = socketEvent.success {
                            Logger.log("iina event success? \(re)")
                        } else {
                            Logger.log("iina event \(socketStr)")
                        }
                    } catch let error {
                        Logger.log("mpvSocket error \(error)")
                    }
                }
            }
        }
    }
    
    
    @objc func foremostAppActivated(_ notification: NSNotification) {
        
        guard let app = notification.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication,
            app.bundleIdentifier == "com.colliderli.iina" else {
                window?.orderOut(self)
                return
        }
        resizeWindow()
    }
    
    func resizeWindow() {
        let tt = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .optionOnScreenAboveWindow], kCGNullWindowID) as? [[String: AnyObject]]
        if let d = tt?.filter ({
            if let owner = $0["kCGWindowOwnerName"] as? String,
                owner == "IINA",
                let title = $0["kCGWindowName"] as? String,
                title == targeTitle {
                return true
            } else {
                return false
            }
        }).first {
            var re = WindowData(d).frame
            re.origin.y = (NSScreen.main?.frame.size.height)! - re.size.height - re.origin.y
            window?.setFrame(re, display: true)
            window?.orderFront(self)
            if waittingSocket {
                initMpvSocket()
                waittingSocket = false
            }
        }
    }
    
    func loadDM(_ data: Data) {
        let danmakuFilePath = Bundle.main.resourcePath! + "/iina-plus-danmaku.xml"
        
        FileManager.default.createFile(atPath: danmakuFilePath, contents: data, attributes: nil)
        
        if let danmakuViewController = self.contentViewController as? DanmakuViewController {
            DispatchQueue.main.async {
                danmakuViewController.webView.evaluateJavaScript("loadDM(\"\(danmakuFilePath)\");") { (_, _) in
                }
            }
        }
    }
    
    func sendDM(_ str: String) {
        if let webView = (self.contentViewController as? DanmakuViewController)?.webView {
            webView.evaluateJavaScript("""
                window.cm.send({'text': "\(str)",'stime': 0,'mode': 1,'color': 0xffffff,'border': false})
            """) { _, _ in
            }
        }
    }
    
}

extension DanmakuWindowController: SRWebSocketDelegate {
    
    func webSocketDidOpen(_ webSocket: SRWebSocket) {
        Logger.log("webSocketDidOpen")
        
        switch liveSite {
        case .bilibili:
            let json = """
{"uid":0,"roomid": \(biliLiveRoomID)}
"""
            //0000 0060 0010 0001 0000 0007 0000 0001
            let data = pack(format: "NnnNN", values: [json.count + 16, 16, 1, 7, 1])
            data.append(json.data(using: .utf8)!)
            try? webSocket.send(data: data as Data)
            
            startTimer()
            
        default:
            break
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        Logger.log("webSocketdidClose \(reason ?? "")")
        switch liveSite {
        case .bilibili:
            timer?.suspend()
        default:
            break
        }
        
        
    }
    
    
    func webSocket(_ webSocket: SRWebSocket, didReceiveMessageWith data: Data) {
        
        switch liveSite {
        case .bilibili:
            var datas: [Data] = []
            var d = data
            while d.count > 20 {
                let head = d.subdata(in: 0..<4)
                let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee }))
                datas.append(d.subdata(in: 16..<endIndex))
                if endIndex < d.endIndex {
                    d = d.subdata(in: endIndex..<d.endIndex)
                } else {
                    d.removeAll()
                }
            }
            
            struct DanmuMsg: Decodable {
                struct ResultObj: Decodable {
                    let msg: String?
                    init(from decoder: Decoder) throws {
                        let unkeyedContainer = try decoder.singleValueContainer()
                        msg = try? unkeyedContainer.decode(String.self)
                    }
                }
                var info: [ResultObj]
            }
            
            datas.compactMap {
                try? JSONDecoder().decode(DanmuMsg.self, from: $0)
                }.compactMap {
                    $0.info.compactMap ({ $0.msg }).first
                }.forEach {
                    sendDM($0)
            }
            
        default:
            break
        }
        
    }
    
    func pack(format: String, values: [Int]) -> NSMutableData {
        let data = NSMutableData()
        
        format.enumerated().forEach {
            let value = values[$0.offset]
            switch $0.element {
            case "n":
                let number: UInt16 = UInt16(value)
                var convertedNumber = CFSwapInt16(number)
                data.append(&convertedNumber, length: 2)
            case "N":
                let number: UInt32 = UInt32(value)
                var convertedNumber = CFSwapInt32(number)
                data.append(&convertedNumber, length: 4)
            default:
                print("Unrecognized character: \($0.element)")
            }
        }
        return data
    }
}

struct WindowData {
    public let name: String
    public let pid: Int
    public let wid: Int
    public let layer: Int
    public let opacity: CGFloat
    public let frame: CGRect
    
    init(_ d: [String: AnyObject]) {
        let _r = d[kCGWindowBounds as String] as? [String: Int]
        frame = NSRect(x: _r?["X"] ?? 0,
                       y: _r?["Y"] ?? 0,
                       width: _r?["Width"] ?? 0,
                       height: _r?["Height"] ?? 0)
        name = d[kCGWindowName as String] as? String ?? ""
        pid = d[kCGWindowOwnerPID as String] as? Int ?? -1
        wid = d[kCGWindowNumber as String] as? Int ?? -1
        layer = d[kCGWindowLayer as String] as? Int ?? 0
        opacity = d[kCGWindowAlpha as String] as? CGFloat ?? 0.0
    }
}




struct MpvSocketEvent: Unmarshaling {
    var event: MpvEvent?
    var id: Int?
    var name: String?
    var data: String?
    var success: Bool?
    
    
    init(object: MarshaledObject) throws {
        let eventStr: String? = try object.value(for: "event")
        event = MpvEvent(rawValue: eventStr ?? "")
        id = try object.value(for: "id")
        name = try object.value(for: "name")
        data = try object.value(for: "data")
        let errorStr: String? = try object.value(for: "error")
        if errorStr != nil {
            success = errorStr == "success"
        }
    }
}


enum MpvEvent: String {
    case propertyChange = "property-change"
    case pause
    case idle
    case unpause
}
