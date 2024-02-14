//
//  AmplitudeSession.swift
//
//  Created by Cody Garvin on 2/16/21.
//

// MIT License
//
// Copyright (c) 2021 Segment
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Segment
import UIKit

@objc(SEGAmplitudeSession)
public class ObjCAmplitudeSession: NSObject, ObjCPlugin, ObjCPluginShim {
    public func instance() -> EventPlugin { return AmplitudeSession() }
}


/// Letting the user provide their own session ID
/// This is to allow to have Amplitude SDK in parallele monitoring session id events
///
/// Temporary workaround for https://github.com/segment-integrations/analytics-swift-amplitude/issues/16
public typealias SessionIDProvider = () -> Int64?

public class AmplitudeSession: EventPlugin, iOSLifecycle {
    public var key = "Actions Amplitude"
    public var type = PluginType.enrichment
    public var analytics: Analytics?
    
    var active = false
    
    private var sessionID: Int64?
    private var lastEventFiredTime = Date()
    private var minSessionTime: TimeInterval = 5 * 60
    
    private let sessionIDProvider: SessionIDProvider?

    public init(sessionIDProvider: SessionIDProvider? = nil) {
        if (sessionID == nil || sessionID == -1)
        {
            sessionID = (Int64(Date().timeIntervalSince1970) * 1000)
        }
        self.sessionIDProvider = sessionIDProvider
    }
    
    public func update(settings: Settings, type: UpdateType) {
        if settings.hasIntegrationSettings(key: key) {
            active = true
        } else {
            active = false
        }
    }
    
    public func execute<T: RawEvent>(event: T?) -> T? {
        if !active {
            return event
        }
        
        var result: T? = event
        switch result {
        case let r as IdentifyEvent:
            result = self.identify(event: r) as? T
            lastEventFiredTime = Date()
        case let r as TrackEvent:
            result = self.track(event: r) as? T
        case let r as ScreenEvent:
            result = self.screen(event: r) as? T
            lastEventFiredTime = Date()
        case let r as AliasEvent:
            result = self.alias(event: r) as? T
            lastEventFiredTime = Date()
        case let r as GroupEvent:
            result = self.group(event: r) as? T
            lastEventFiredTime = Date()
        default:
            break
        }
        return result
    }
    
    public func track(event: TrackEvent) -> TrackEvent? {
        if event.event != "Application Opened" {
            lastEventFiredTime = Date()
        }
        
        guard let returnEvent = insertSession(event: event) as? TrackEvent else {
            return nil
        }
        return returnEvent
    }
    
    public func identify(event: IdentifyEvent) -> IdentifyEvent? {
        guard let returnEvent = insertSession(event: event) as? IdentifyEvent else {
            return nil
        }
        return returnEvent
    }
    
    public func alias(event: AliasEvent) -> AliasEvent? {
        guard let returnEvent = insertSession(event: event) as? AliasEvent else {
            return nil
        }
        return returnEvent
    }
    
    public func screen(event: ScreenEvent) -> ScreenEvent? {
        guard let returnEvent = insertSession(event: event) as? ScreenEvent else {
            return nil
        }
        return returnEvent
    }
    
    public func group(event: GroupEvent) -> GroupEvent? {
        guard let returnEvent = insertSession(event: event) as? GroupEvent else {
            return nil
        }
        return returnEvent
    }
    
    public func reset() {
         sessionID = nil
    }
    
    public func applicationWillEnterForeground(application: UIApplication?) {
        if let sessionIDProvider = sessionIDProvider {
            sessionID = sessionIDProvider()
        } else if Date().timeIntervalSince(lastEventFiredTime) >= minSessionTime {
            sessionID = (Int64(Date().timeIntervalSince1970) * 1000)
        }
        
        analytics?.log(message: "Amplitude Session ID: \(sessionID ?? -1)")
    }
    
    public func applicationWillResignActive(application: UIApplication?) {
        // Exposed if reacting to lifecycle events is needed
    }
    
}


// MARK: - AmplitudeSession Helper Methods
extension AmplitudeSession {
    func insertSession(event: RawEvent) -> RawEvent {
        var returnEvent = event
        if var integrations = event.integrations?.dictionaryValue,
           let sessionID = sessionIDProvider?() ?? sessionID {

            integrations[key] = ["session_id": sessionID]
            returnEvent.integrations = try? JSON(integrations as Any)
        }
        return returnEvent
    }
}

extension AmplitudeSession: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
}
