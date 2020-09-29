//
//  main.swift
//  bridge-monitor-gaps
//
//  Created by Eric Ferreira on 9/29/20.
//  Copyright © 2020 ferreira.life. All rights reserved.
//

import Cocoa

let delegate = AppDelegate()

NSApplication.shared.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
