//
//  IINAApp.swift
//  IINA+
//
//  Created by xjbeta on 2023/7/15.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

class IINAApp: NSObject {
	
	enum IINAError: Error {
		case cannotUnpackage
		case onlyDevPlugin
	}
	
	
	struct PluginInfo: Decodable {
		let name: String
		let identifier: String
		let version: String
		let ghVersion: Int
		
		var path = ""
		var isDev = false
		
		enum CodingKeys: CodingKey {
			case name, identifier, version, ghVersion
		}
	}
	
	func buildVersion() -> Int {
		let b = Bundle(path: "/Applications/IINA.app")
		let build = b?.infoDictionary?["CFBundleVersion"] as? String ?? ""
		return Int(build) ?? 0
	}
	
	func archiveType() -> IINAUrlType {
		let build = buildVersion()
		
		let b = Bundle(path: "/Applications/IINA.app")
		guard let version = b?.infoDictionary?["CFBundleShortVersionString"] as? String else {
			return .none
		}
		if version.contains("Danmaku") {
			return .danmaku
		} else if version.contains("plugin") {
			return .plugin
		} else if build >= 135 {
			return .plugin
		}
		return .normal
	}
	
	func pluginFolder() throws -> String {
//		/Users/xxx/Library/Application Support/com.colliderli.iina/plugins
		let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
		let path = url.path + "/com.colliderli.iina/plugins/"
		return path
	}
	
	func listPlugins() throws -> [PluginInfo] {
		let fm = FileManager.default
		let path = try pluginFolder()
		return try fm.contentsOfDirectory(atPath: path).filter {
			$0.hasSuffix("iinaplugin") || $0.hasSuffix("iinaplugin-dev")
		}.compactMap {
			let isDev = $0.hasSuffix("iinaplugin-dev")
			
			guard let data = fm.contents(atPath: path + $0 + "/" + "Info.json"),
				  var info = try? JSONDecoder().decode(PluginInfo.self, from: data) else { return nil }
			
			info.path = path + $0
			info.isDev = isDev
			return info
		}.filter {
			$0.identifier == "com.xjbeta.danmaku"
		}
	}
	
	func uninstallPlugins() throws {
		let plugins = try listPlugins()
		if plugins.count == 1,
		   plugins[0].isDev {
			throw IINAError.onlyDevPlugin
		}
		
		plugins.filter {
			!$0.isDev
		}.forEach {
			try? FileManager.default.removeItem(atPath: $0.path)
		}
	}
	
	func installPlugin() throws {
		guard let path = Bundle.main.path(forResource: "iina-plugin-danmaku", ofType: "iinaplgz") else { return }
		
		// IINA create(fromPackageURL url: URL)
		
		Log("Installing plugin from file: \(path)")

		let pluginsRoot = try pluginFolder()
		let tempFolder = ".temp.\(UUID().uuidString)"
		let tempZipFile = "\(tempFolder).zip"
		let tempDecompressDir = "\(tempFolder)-1"

		defer {
		  [tempZipFile, tempDecompressDir].forEach { item in
			try? FileManager.default.removeItem(atPath: pluginsRoot + item)
		  }
		}

		func removeTempPluginFolder() {
		  try? FileManager.default.removeItem(atPath: pluginsRoot + tempFolder)
		}
		
		let cmd = [
		  "cp '\(path)' '\(tempZipFile)'",
		  "mkdir '\(tempFolder)' '\(tempDecompressDir)'",
		  "unzip '\(tempZipFile)' -d '\(tempDecompressDir)'",
		  "mv '\(tempDecompressDir)'/* '\(tempFolder)'/"
		].joined(separator: " && ")
		let (process, stdout, stderr) = Process.run(["/bin/bash", "-c", cmd], at: .init(fileURLWithPath: pluginsRoot))

		guard process.terminationStatus == 0 else {
		  let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
		  let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
		  removeTempPluginFolder()
			throw IINAError.cannotUnpackage
		}
	}
}
