//
//  AppDelegate.swift
//  bridge-monitor-gaps
//
//  Created by Eric Ferreira on 5/15/20.
//  Copyright © 2020 ferreira.life. All rights reserved.
//

import Cocoa
import SwiftUI

enum Direction {
    case horizontal
    case horizontalGap
    case vertical
    case verticalGap
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var screensCheckTimer: Timer!
    
    var local: Any?
    var global: Any?
    var mouseMovingCheckTimer: Timer?
    var mousePositionCheckTimer: Timer?
    
    var lastMousePosition = NSEvent.mouseLocation
    
    var screens: [CGRect] = []
    var zones: [(Direction, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)]!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Populate the jump zones for the screen layout at start
        checkZones()

        // Check every once in a while if the screens have changed positions
        screensCheckTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true, block: checkZones)
        
        // Remove the pause when warping the mouse position
        CGEventSource(stateID: CGEventSourceStateID.combinedSessionState)?.localEventsSuppressionInterval = 0;
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        screensCheckTimer.invalidate()
        stopListeners()
    }
    
    func eventHandler(_ event: NSEvent) {
        parseMousePosition(event.locationInWindow)
    }
    
    func startListener() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        
        if local == nil {
            // Receive local events for mouse movement
            local = NSEvent.addLocalMonitorForEvents(matching: events) { event in
                self.eventHandler(event)
                
                return event
            }
        }
        
        if global == nil {
            // Receive global events for mouse movement
            global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: eventHandler)
        }
        
        if mouseMovingCheckTimer == nil {
            // We need to fall back to polling when events are not fired (when launchpad, mission control, etc is pulled up)
            // This only checks if polling should be enabled. If it is, polling is enabled in the passed function.
            mouseMovingCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: checkMouseIsMoving)
        }
    }
    
    func stopListeners() {
        if local != nil {
            NSEvent.removeMonitor(local!)
            local = nil
        }
        
        if global != nil {
            NSEvent.removeMonitor(global!)
            global = nil
        }
        
        if mouseMovingCheckTimer != nil {
            mouseMovingCheckTimer!.invalidate()
            mouseMovingCheckTimer = nil
        }
        
        if mousePositionCheckTimer != nil {
            mousePositionCheckTimer!.invalidate()
            mousePositionCheckTimer = nil
        }
    }
    
    func moveTo(_ x: CGFloat, _ y: CGFloat) {
        CGWarpMouseCursorPosition(CGPoint(x: x, y: screens[0].size.height - y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }
    
    func filterPairs(_ arr: [CGFloat]) -> [CGFloat] {
        return arr.enumerated().filter { (i, el) in
            if i % 2 == 0 && el == arr[i + 1] {
                return false
            }
            
            if i % 2 == 1 && el == arr[i - 1] {
                return false
            }
            
            return true
        }.map { $0.element }
    }
    
    func checkZones(_: Timer? = nil) {
        let latestScreens = NSScreen.screens
        
        if screens.count == latestScreens.count {
            var equal = true

            for (index, screen) in screens.enumerated() {
                if screen != latestScreens[index].frame {
                    equal = false
                    
                    break
                }
            }
            
            if equal {
                return
            }
        }
        
        zones = []
        screens = latestScreens.map { $0.frame }
        
        for screen in screens {
            let top = screen.maxY
            let bottom = screen.minY
            let right = screen.maxX
            let left = screen.minX
            
            let upwards = screens.filter { s in top <= s.minY && s.minX <= right && left <= s.maxX && !screens.contains(where: { top <= $0.minY && $0.maxY <= s.minY })}.sorted { $0.minX < $1.minX }
            let rightwards = screens.filter { s in right <= s.minX && s.minY <= top && bottom <= s.maxY && !screens.contains(where: { right <= $0.minX && $0.maxX <= s.minX })}.sorted { $0.minY < $1.minY }
            let downwards = screens.filter { s in bottom >= s.maxY && s.minX <= right && left <= s.maxX && !screens.contains(where: { bottom >= $0.maxY && $0.minY >= s.maxY })}.sorted { $0.minX < $1.minX }
            let leftwards = screens.filter { s in left >= s.maxX && s.minY <= top && bottom <= s.maxY && !screens.contains(where: { left >= $0.maxX && $0.minX >= s.maxX })}.sorted { $0.minY < $1.minY }
            
            zones += rightwards.filter { right != $0.minX }.map { other in
                let otherTop = other.maxY
                let otherBottom = other.minY
                let otherLeft = other.minX
                
                return (.horizontal, max(bottom, otherBottom), min(top, otherTop), right, otherLeft, CGFloat.nan)
            }
            
            zones += upwards.filter { top != $0.minY }.map { other in
                let otherRight = other.maxX
                let otherBottom = other.minY
                let otherLeft = other.minX
                
                return (.vertical, max(left, otherLeft), min(right, otherRight), top, otherBottom, CGFloat.nan)
            }
            
            if !upwards.isEmpty {
                var gaps = filterPairs(upwards.reduce([left, right]) { res, next in
                    var res = res
                    
                    if next.minX < left {
                        res[0] = next.maxX
                    } else if next.maxX > right {
                        res[res.count - 1] = next.minX
                    } else {
                        res.insert(contentsOf: [next.minX, next.maxX], at: res.count - 1)
                    }
                    
                    return res
                })
                
                if !gaps.isEmpty {
                    if !screens.contains(where: { other in
                        return other.maxX <= gaps[0] && other.maxY > top
                    }) {
                        gaps.removeSubrange(0..<2)
                    }
                    
                    if !gaps.isEmpty {
                        if !screens.contains(where: { other in
                            return other.minX >= gaps.last! && other.maxY > top
                        }) {
                            gaps.removeSubrange((gaps.count - 2)..<gaps.count)
                        }
                        
                        if !gaps.isEmpty {
                            for i in 0..<(gaps.count / 2) {
                                let i = i * 2
                                let toX = gaps[i] > bottom ? gaps[i] - 1 : gaps[i + 1] + 1
                                let toY = upwards.first { $0.minX < toX && toX < $0.maxX }!
                                
                                zones += [(.verticalGap, gaps[i], gaps[i + 1], top, toX, toY.minY + 1)]
                            }
                        }
                    }
                }
            }
            
            if !rightwards.isEmpty {
                var gaps = filterPairs(rightwards.reduce([bottom, top]) { res, next in
                    var res = res
                    
                    if next.minY < bottom {
                        res[0] = next.maxY
                    } else if next.maxY > top {
                        res[res.count - 1] = next.minY
                    } else {
                        res.insert(contentsOf: [next.minY, next.maxY], at: res.count - 1)
                    }
                    
                    return res
                })
                
                if !gaps.isEmpty {
                    if !screens.contains(where: { other in
                        return other.maxY <= gaps[0] && other.maxX > right
                    }) {
                        gaps.removeSubrange(0..<2)
                    }
                    
                    if !gaps.isEmpty {
                        if !screens.contains(where: { other in
                            return other.minY >= gaps.last! && other.maxX > right
                        }) {
                            gaps.removeSubrange((gaps.count - 2)..<gaps.count)
                        }
                        
                        if !gaps.isEmpty {
                            for i in 0..<(gaps.count / 2) {
                                let i = i * 2
                                let toY = gaps[i] > bottom ? gaps[i] - 1 : gaps[i + 1] + 1
                                let toX = rightwards.first { $0.minY < toY && toY < $0.maxY }!
                                
                                zones += [(.horizontalGap, gaps[i], gaps[i + 1], right, toX.minX + 1, toY),]
                            }
                        }
                    }
                }
            }
            
            if !downwards.isEmpty {
                var gaps = filterPairs(downwards.reduce([left, right]) { res, next in
                    var res = res
                    
                    if next.minX < left {
                        res[0] = next.maxX
                    } else if next.maxX > right {
                        res[res.count - 1] = next.minX
                    } else {
                        res.insert(contentsOf: [next.minX, next.maxX], at: res.count - 1)
                    }
                    
                    return res
                })
                
                if !gaps.isEmpty {
                    if !screens.contains(where: { other in
                        return other.maxX <= gaps[0] && other.minY < bottom
                    }) {
                        gaps.removeSubrange(0..<2)
                    }
                    
                    if !gaps.isEmpty {
                        if !screens.contains(where: { other in
                            return other.minX >= gaps.last! && other.minY < bottom
                        }) {
                            gaps.removeSubrange((gaps.count - 2)..<gaps.count)
                        }
                        
                        if !gaps.isEmpty {
                            for i in 0..<(gaps.count / 2) {
                                let i = i * 2
                                let toX = gaps[i] > left ? gaps[i] - 1 : gaps[i + 1] + 1
                                let toY = downwards.first { $0.minX < toX && toX < $0.maxX }!

                                zones += [(.verticalGap, gaps[i], gaps[i + 1], bottom, toX, toY.maxY - 1),]
                            }
                        }
                    }
                }
            }
            
            if !leftwards.isEmpty {
                var gaps = filterPairs(leftwards.reduce([bottom, top]) { res, next in
                    var res = res
                    
                    if next.minY < bottom {
                        res[0] = next.maxY
                    } else if next.maxY > top {
                        res[res.count - 1] = next.minY
                    } else {
                        res.insert(contentsOf: [next.minY, next.maxY], at: res.count - 1)
                    }
                    
                    return res
                })
                
                if !gaps.isEmpty {
                    if !screens.contains(where: { other in
                        return other.maxY <= gaps[0] && other.minX < left
                    }) {
                        gaps.removeSubrange(0..<2)
                    }
                    
                    if !gaps.isEmpty {
                        if !screens.contains(where: { other in
                            return other.minY >= gaps.last! && other.minX < left
                        }) {
                            gaps.removeSubrange((gaps.count - 2)..<gaps.count)
                        }
                        
                        if !gaps.isEmpty {
                            for i in 0..<(gaps.count / 2) {
                                let i = i * 2
                                let toY = gaps[i] > bottom ? gaps[i] - 1 : gaps[i + 1] + 1
                                let toX = leftwards.first { $0.minY < toY && toY < $0.maxY }!

                                zones += [(.horizontalGap, gaps[i], gaps[i + 1], left, toX.maxX - 1, toY),]
                            }
                        }
                    }
                }
            }
        }
        
        if !zones.isEmpty  {
            startListener()
        } else {
            stopListeners()
        }
    }
    
    func checkMouseIsMoving(_: Timer? = nil) {
        let mousePosition = NSEvent.mouseLocation
        
        if round(lastMousePosition.x * 100) != round(mousePosition.x * 100) && round(lastMousePosition.y * 100) != round(mousePosition.y * 100) {
            if mousePositionCheckTimer == nil {
                mousePositionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
                    self.parseMousePosition(NSEvent.mouseLocation)
                }
            }
        } else {
            mousePositionCheckTimer?.invalidate()
            mousePositionCheckTimer = nil
        }
    }
    
    func parseMousePosition(_ loc: CGPoint) {
        lastMousePosition = loc
        
        let x = round(loc.x)
        let y = round(loc.y)
        
        for zone in zones {
            switch zone.0 {
                case .horizontal:
                    if zone.1 <= y && y < zone.2 {
                        if x == zone.3 {
                            moveTo(zone.4 + 1, y)
                        } else if x == zone.4 {
                            moveTo(zone.3 - 1, y)
                        }
                    }
                case .horizontalGap:
                    if zone.1 <= y && y <= zone.2 {
                        if x == zone.3 {
                            moveTo(zone.4, zone.5)
                        }
                    }
                case .vertical:
                    if zone.1 <= x && x < zone.2 {
                        if y == zone.3 {
                            moveTo(x, zone.4 + 1)
                        } else if y == zone.4 {
                            moveTo(x, zone.3 - 1)
                        }
                    }
                case .verticalGap:
                    if zone.1 <= x && x <= zone.2 {
                        if y == zone.3 {
                            moveTo(zone.4, zone.5)
                        }
                    }
            }
        }
    }
}



