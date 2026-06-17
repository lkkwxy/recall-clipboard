//
//  LaunchAtLogin.swift
//  Recall
//
//  开机自启动。状态以系统为准（SMAppService），不落 UserDefaults，避免与系统真实状态不一致。
//

import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 切换自启动；失败时抛出，由调用方提示用户。
    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
