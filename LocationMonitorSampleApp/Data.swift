//
//  Data.swift
//  LocationMonitorSampleApp
//
//  Created by James Clarke on 10/21/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import SwiftData
import CoreLocation


extension CLMonitor.Event.State {
    var description : String {
       switch self {
       // Use Internationalization, as appropriate.
       case .satisfied: return "Satisfied"
       case .unknown: return "unknown"
       case .unmonitored: return "unmonitored"
       case .unsatisfied: return "unsatisfied"
       default: return "other"
       }
     }
}

@Model
class LMEvent
{
    init(date: Date, identifier: String, state: CLMonitor.Event.State) {
        self.date = date
        self.identifier = identifier
        self.state = state.description
    }
    
    var date: Date?
    var identifier: String?
    var state: String?
}
