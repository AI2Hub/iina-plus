//
//  QQLive.swift
//  IINA+
//
//  Created by xjbeta on 6/9/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import PMKAlamofire
import Marshal

class QQLive: NSObject, SupportSiteProtocol {
	lazy var pSession: Session = {
		let configuration = URLSessionConfiguration.af.default
		let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
		configuration.headers.add(.userAgent(ua))
		return Session(configuration: configuration)
	}()
	
    func liveInfo(_ url: String) -> Promise<LiveInfo> {
        roomInfo(url).map {
            $0 as LiveInfo
        }
    }
    
    func decodeUrl(_ url: String) -> Promise<YouGetJSON> {
        mInfo(url).map {
            var re = YouGetJSON(rawUrl: url)
            re.title = $0.title
			re.streams["Default"] = .init(url: $0.url.replacingOccurrences(of: "http://", with: "https://"))
            return re
        }
    }
	
	func roomInfo(_ url: String) -> Promise<QQLiveInfo> {
		AF.request(url).responseString().map {
			$0.string
				.subString(from: #"__NEXT_DATA__"#, to: "</script>")
				.subString(from: ">")
		}.map {
			guard let data = $0.data(using: .utf8) else { throw VideoGetError.notFountData }
			
			let json: JSONObject = try JSONParser.JSONObjectWithData(data)
			return try QQLiveInfo(object: json)
		}
	}
    
    func mInfo(_ url: String) -> Promise<QQLiveMInfo> {
		let url = url.replacingOccurrences(of: "https://live.qq.com", with: "https://m.live.qq.com")
		
		return pSession.request(url).responseString().map {
			$0.string.subString(from: "window.$ROOM_INFO = ", to: ";</script>")
		}.map {
			guard let data = $0.data(using: .utf8) else { throw VideoGetError.notFountData }
			
			let json: JSONObject = try JSONParser.JSONObjectWithData(data)
			return try QQLiveMInfo(object: json)
		}
    }
}

struct QQLiveInfo: Unmarshaling, LiveInfo {
	var title: String = ""
	var name: String = ""
	var avatar: String
	var isLiving = false
	var cover: String = ""
	var site: SupportSites = .qqLive
	
	var roomID: String = ""
	
	init(object: MarshaledObject) throws {
		
		let roomInfoPath = "props.initialState.roomInfo.roomInfo.room_info"
		
		title = try object.value(for: "\(roomInfoPath).room_name")
		name = try object.value(for: "\(roomInfoPath).nickname")
		isLiving = "\(try object.any(for: "\(roomInfoPath).is_live"))" == "1"
		cover = try object.value(for: "\(roomInfoPath).room_src_square")
		roomID = try object.value(for: "\(roomInfoPath).room_id")
		
		let uid: String = try object.value(for: "\(roomInfoPath).owner_uid")
		let avatarCDN: String = try object.value(for: "runtimeConfig.AVATAR_CDN")
		avatar = "https:" + avatarCDN + "/avatar.php?uid=\(uid)&size=middle&force=1"
		
	}
}
	

struct QQLiveMInfo: Unmarshaling, LiveInfo {
    var title: String = ""
    var name: String = ""
    var avatar: String
    var isLiving = false
    var cover: String = ""
    var site: SupportSites = .qqLive
    
	var roomID: String = ""
	
    var url: String
    
    init(object: MarshaledObject) throws {
		
        title = try object.value(for: "room_name")
        name = try object.value(for: "nickname")
        isLiving = "\(try object.any(for: "show_status"))" == "1"
        cover = try object.value(for: "room_src")
		roomID = try object.value(for: "room_id")
		
		avatar = try object.value(for: "owner_avatar")
		
        url = try object.value(for: "rtmp_url") + "/" + object.value(for: "rtmp_live")
    }
}
