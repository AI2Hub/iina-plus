//
//  DanmakuViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/28.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal
import SocketRocket
import Gzip

class DanmakuViewController: NSViewController {
    
    @IBOutlet weak var webView: WKWebView!
    
    // Resource files
    let danmakuFilePath = Bundle.main.path(forResource: "iina-plus-danmaku", ofType: "xml")
    
    var socket: SRWebSocket? = nil
    var liveSite: LiveSupportList = .unsupported
    
    let biliLiveServer = URL(string: "wss://broadcastlv.chat.bilibili.com/sub")
    var biliLiveRoomID = 0
    var pandaInitStr = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView.setValue(false, forKey: "drawsBackground")
        
        if let resourcePath = Bundle.main.resourcePath {
            let u1 = URL(fileURLWithPath: resourcePath + "/index.htm")
            webView.loadFileURL(u1, allowingReadAccessTo: URL(fileURLWithPath: resourcePath))
        }
    }
    
    func initDanmaku(_ site: LiveSupportList, _ url: String) {
        if let danmakuFilePath = danmakuFilePath {
            try? FileManager.default.removeItem(atPath: danmakuFilePath)
        }
        
        socket?.close()
        socket = nil
        
        self.initDM()
        
        
        liveSite = site
        switch site {
        case .bilibili:
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
        case .biliLive:
            socket = SRWebSocket(url: biliLiveServer!)
            socket?.delegate = self

            let roomID = URL(string: url)?.lastPathComponent ?? ""

            HTTP.GET("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)") {
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data)
                    self.biliLiveRoomID = try json.value(for: "data.room_id")
                    self.socket?.open()
                } catch let error {
                    Logger.log("can't find bilibili live room id \(error)")
                }
            }
        case .panda:
            let roomID = URL(string: url)?.lastPathComponent ?? ""
            HTTP.GET("https://riven.panda.tv/chatroom/getinfo?roomid=\(roomID)&protocol=ws") {
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data)
                    let pandaInfo = try PandaChatRoomInfo(object: json)

                    self.pandaInitStr = pandaInfo.initStr()
                    self.socket = SRWebSocket(url: pandaInfo.chatAddr!)
                    self.socket?.delegate = self
                    self.socket?.open()
                } catch let error {
                    Logger.log("can't find panda live room id \(error)")
                }
            }
        default:
            break
        }
    }
    
    func testedBilibiliAPI() {
        let p = ["aid": 31027408,
                 "appkey": "1d8b6e7d45233436",
                 "build": 5310000,
                 "mobi_app": "android",
                 "oid": 54186450,
                 "plat":2,
                 "platform": "android",
                 "ps": 0,
                 "ts": 1536407932,
                 "type": 1,
                 "sign": 0] as [String : Any]
        HTTP.GET("https://api.bilibili.com/x/v2/dm/list.so", parameters: p) { re in
            let data = re.data
            let head = data.subdata(in: 0..<4)
            let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee })) + 4
            let d1 = data.subdata(in: 4..<endIndex)
            
            let d2 = data.subdata(in: endIndex..<data.endIndex)
            
            let d3 = try! d2.gunzipped()
            
            let str1 = String(data: d1, encoding: .utf8)
            let str2 = String(data: d3, encoding: .utf8)
            
//            FileManager.default.createFile(atPath: "/Users/xjbeta/Downloads/d1", contents: d1, attributes: nil)
//            
//            FileManager.default.createFile(atPath: "/Users/xjbeta/Downloads/d2", contents: d3, attributes: nil)
            
        }
        
        
        
        
    }
    
    private var timer: DispatchSourceTimer?
    
    private let timerQueue = DispatchQueue(label: "com.xjbeta.iina+.WebSocketKeepLive")
    
    private func startTimer() {
        timer?.cancel()
        timer = nil
        timer = DispatchSource.makeTimerSource(flags: [], queue: timerQueue)
        if let timer = timer {
            timer.schedule(deadline: .now(), repeating: .seconds(30))
            timer.setEventHandler {
                switch self.liveSite {
                case .biliLive:
                    try? self.socket?.send(data: self.pack(format: "NnnNN", values: [16, 16, 1, 2, 1]) as Data)
                case .panda:
                    try? self.socket?.send(data: self.pack(format: "nn", values: [6, 0]) as Data)
                default:
                    break
                }
            }
            timer.resume()
        }
    }
    
    
    
    func initMpvSocket() {
        Logger.log("initMpvSocket")
        var isPasued = false
        Processes.shared.mpvSocket({ socketEvent in
            if let event = socketEvent.event {
                switch event {
                case .pause:
                    guard self.liveSite == .bilibili else { return }
                    self.evaluateJavaScript("window.cm.stop();")
                    isPasued = true
                    Logger.log("iina pasued")
                case .unpause:
                    guard self.liveSite == .bilibili else { return }
                    self.evaluateJavaScript("window.cm.start();")
                    isPasued = false
                    Logger.log("iina unpause")
                case .propertyChange:
                    if socketEvent.name == "time-pos" {
                        guard self.liveSite == .bilibili else { return }
                        guard let timeStr = socketEvent.data, let time = Double(timeStr), !isPasued else {
                            return
                        }
                        self.evaluateJavaScript("window.cm.time(Math.floor(\(time * 1000)));")
                        //                                    Logger.log("iina seek")
                    } else if socketEvent.name == "window-scale" {
                        self.danmakuWindowController {
                            $0.resizeWindow()
                        }
                        self.evaluateJavaScript("window.resize();")
                        Logger.log("iina window-scale")
                    }
                case .idle:
                    self.danmakuWindowController {
                        $0.window?.orderOut(nil)
                    }
                    Logger.log("iina idle")
                }
            } else if let re = socketEvent.success {
                Logger.log("iina event success? \(re)")
            }
        }) {
            self.socket?.close()
            self.socket = nil
            Logger.log("mpv socket disconnected")
        }
    }
    
    func danmakuWindowController(_ windowController: @escaping (DanmakuWindowController) -> Void) {
        DispatchQueue.main.async {
            if let danmakuWindowController = self.view.window?.windowController as? DanmakuWindowController {
                windowController(danmakuWindowController)
            }
        }
    }
    
    func loadDM(_ data: Data) {
        if let resourcePath = Bundle.main.resourcePath {
            let danmakuFilePath = resourcePath + "/iina-plus-danmaku.xml"
            FileManager.default.createFile(atPath: danmakuFilePath, contents: data, attributes: nil)
            evaluateJavaScript("loadDM(\"\(danmakuFilePath)\");")
            Logger.log("loadDM in \(danmakuFilePath)")
        }
    }
    
    func initDM() {
        evaluateJavaScript("window.initDM();")
    }
    
    func sendDM(_ str: String) {
        print("sendDM \(str)")
        evaluateJavaScript("""
window.cm.send({'text': "\(str)",'stime': 0,'mode': 1,'color': 0xffffff,'border': false});
""")
    }
    
    func evaluateJavaScript(_ str: String) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(str) { _, error in
                if let error = error {
                    Logger.log("webView.evaluateJavaScript error \(error)")
                }
            }
        }
    }
    
    func sendDebugDM(_ str: String) {
        print("sendDebugDM \(str)")
        evaluateJavaScript("""
            window.cm.send({'text': "\(str)",'stime': 0,'mode': 4, 'align': 2,'color': 0xffffff,'border': false});
            """)
    }
    
    
}


extension DanmakuViewController: SRWebSocketDelegate {
    
    func webSocketDidOpen(_ webSocket: SRWebSocket) {
        Logger.log("webSocketDidOpen")
        
        switch liveSite {
        case .biliLive:
            let json = """
            {"uid":0,"roomid": \(biliLiveRoomID)}
            """
            //0000 0060 0010 0001 0000 0007 0000 0001
            let data = pack(format: "NnnNN", values: [json.count + 16, 16, 1, 7, 1])
            data.append(json.data(using: .utf8)!)
            try? webSocket.send(data: data as Data)
            startTimer()
        case .panda:
            //0006 0002 00DA
            let data = pack(format: "nnn", values: [6, 2, pandaInitStr.count])
            data.append(pandaInitStr.data(using: .utf8)!)
            try? webSocket.send(data: data as Data)
            startTimer()
        default:
            break
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        Logger.log("webSocketdidClose \(reason ?? "")")
        switch liveSite {
        case .biliLive, .panda:
            timer?.cancel()
            timer = nil
        default:
            break
        }
        
        
    }
    
    
    func webSocket(_ webSocket: SRWebSocket, didReceiveMessageWith data: Data) {
        
        switch liveSite {
        case .biliLive:
            //            0000 0234
            //            0-4 json length + head
            
            if data.count == 20 {
                Logger.log("received heartbeat")
            } else if data.count == 16 {
                Logger.log("connect success")
            }
            
            var datas: [Data] = []
            var d = data
            while d.count > 20 {
                let head = d.subdata(in: 0..<4)
                let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee }))
                
                if endIndex <= d.endIndex {
                    datas.append(d.subdata(in: 16..<endIndex))
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
            
        case .panda:
            //            00 06 00 03 00 05 61 63 6B 3A 30 00 00 02 A9 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 48
            //            0 - 15 mark
            //
            //            00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 41
            //            01 41 json length
            if data.count == 4 {
                Logger.log("received heartbeat")
            } else if data.count == 22 {
                Logger.log("connect success")
            }
            
            var datas: [Data] = []
            var d = data
            guard d.count > 15 else { return }
            d = d.subdata(in: 15..<d.endIndex)
            
            while d.count > 22 {
                let head = d.subdata(in: 12..<16)
                let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee })) + 16
                
                if endIndex <= d.endIndex {
                    datas.append(d.subdata(in: 16..<endIndex))
                    d = d.subdata(in: endIndex..<d.endIndex)
                } else {
                    d.removeAll()
                }
            }
            
            
            datas.compactMap { data -> String? in
                do {
                    let json = try JSONParser.JSONObjectWithData(data)
                    let type: String = try json.value(for: "type")
                    if type == "1" {
                        let str: String = try json.value(for: "data.content")
                        return str
                    } else {
                        return nil
                    }
                } catch let error {
                    print(error)
                    print(String(data: data, encoding: .utf8))
                    return nil
                }
                }.forEach {
                    sendDM($0)
            }
            
            //            😍[:喜欢]
            //            😢[:哭]
            //            😠[:闭嘴]
            //            😪[:睡]
            //            😺[:惊讶]
            //            😎[:酷]
            //            💦[:流汗]
            //            💪[:努力]
            //            💢[:愤怒]
            //            🤔️[:疑问]
            //            😵[:晕]
            //            🤯[:疯]
            //            😱[:哀]
            //            💀[:骷髅]
            //            😳[:害羞]
            //            🤪[:抠鼻]
            //            😑[:呵欠]
            //            👎[:鄙视]
            //            🎉[:撒花]
            //            😚[:亲]
            //            😞[:可怜]
            //            🤣[:233]
            //            👏[:666]
            
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

struct PandaChatRoomInfo: Unmarshaling {
    var appid: String
    var rid: Int
    var sign: String
    var authType: String
    var ts: Int
    var chatAddr: URL?
    
    init(object: MarshaledObject) throws {
        appid = try object.value(for: "data.appid")
        rid = try object.value(for: "data.rid")
        sign = try object.value(for: "data.sign")
        authType = try object.value(for: "data.authType")
        ts = try object.value(for: "data.ts")
        let chatList: [String]  = try object.value(for: "data.chat_addr_list")
        if let str = chatList.first, let url = URL(string: "wss://" + str) {
            chatAddr = url
        }
    }
    
    func initStr() -> String {
        return """
        u:\(rid)@\(appid)
        ts:\(ts)
        sign:\(sign)
        authtype:\(authType)
        plat:jssdk_pc_web
        version:0.5.10
        network:unknown
        compress:none
        """
    }
}
