/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's main view.
*/

import SwiftUI
import CoreLocation
import SwiftData

let monitorName = "SampleMonitor"
let appleParkLocation = CLLocationCoordinate2D(latitude: 47.650441, longitude: -122.117848)
let testBeaconId = UUID(uuidString: "FDA50693-A4E2-4FB1-AFCF-C6EB07647825")!

let globalAuthDeniedError = "Please enable Location Services by going to Settings -> Privacy & Security"
let authDeniedError = "Please authorize LocationMonitorSampleApp to access Location Services"
let authRestrictedError = "LocationMonitorSampleApp can't access your location. Do you have Parental Controls enabled?"
let accuracyLimitedError = "LocationMonitorSampleApp can't function without access to your precise location"
let alwaysAuthDeniedError = "LocationMonitorSampleApp only works in the foreground without authorization to access your location at all times."
let sessionInactiveError = "This app has the Explicit Session Control key set True. It won't have location access without an active CLServiceSession."

extension UserDefaults {
    
    @objc var authSessionActive: Bool {
        get { return bool(forKey: "authSessionActive") }
        set { set(newValue, forKey: "authSessionActive") }
    }
}

@MainActor
public class ObservableMonitorModel: ObservableObject {
    
    //private let manager: CLLocationManager
    
    // The model doesn't read the published variables. The system only writes them to drive the UI.
    // The CLMonitor state is the only source of truth.
    static let shared = ObservableMonitorModel()
    public var monitor: CLMonitor?
    @Published var UIRows: [String: [CLMonitor.Event]] = [:]
    
    @Published var lastDiagnosticUpdate: CLServiceSession.Diagnostic?
    @Published var authSessionActive: Bool = UserDefaults.standard.bool(forKey: "authSessionActive") {
        didSet {
            authSessionActive ? startAuthSession() : authSession?.invalidate()
            UserDefaults.standard.setValue(authSessionActive, forKey: "authSessionActive")
        }
    }
    private var authSession: CLServiceSession?
    private let notificationCenter = UNUserNotificationCenter.current()
    private var notificationContent = UNMutableNotificationContent()
    
    init() {
        //self.manager = CLLocationManager()
        //self.manager.requestWhenInUseAuthorization()
        notificationContent.title = "Location monitoring inactive"
        notificationContent.body = "Can't receive condition events while not in the foreground"
        
        Task {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge])
        }
    }
    
    func startAuthSession() {
        Task {
            print("Listening to session diagnostics")
            authSession = CLServiceSession(authorization: .always, fullAccuracyPurposeKey: "monitor")
            for try await diagnostics in authSession!.diagnostics {
                lastDiagnosticUpdate = diagnostics
                let notification = UNNotificationRequest(identifier: "com.example.mynotification", content: notificationContent, trigger: nil)
                if diagnostics.insufficientlyInUse {
                    //try await UNUserNotificationCenter.current().add(notification)
                }
            }
        }
    }
    
    func startMonitoringConditions() {
        Task {
            let container = try ModelContainer(for: LMEvent.self)
            let context = ModelContext(container)
            print("Set up monitor")
            monitor = await CLMonitor(monitorName)
            
            await monitor!.add(getCircularGeographicCondition(), identifier: "ApplePark")
            await monitor!.add(getBeaconIdentityCondition(), identifier: "TestBeacon")
            for identifier in await monitor!.identifiers {
                guard let lastEvent = await monitor!.record(for: identifier)?.lastEvent else { continue }
                UIRows[identifier] = [lastEvent]
            }
            for try await event in await monitor!.events {
                // While handling the most recent event, the last event is still updating
                // and shows the prior state, allowing you to reference both.
                guard let lastEvent = await monitor!.record(for: event.identifier)?.lastEvent else { continue }
                
                if event.state == lastEvent.state {
                    // If the event state is the same as the previous state, the only new information is in diagnostics.
                    // Because the event isn't a new state, don't record it in your UI.
                    // Because you respond to service session diagnostics, you don't need to also worry about the ones delivered by the monitor.
                    continue
                }
                UIRows[event.identifier] = [event]
                UIRows[event.identifier]?.append(lastEvent)
                let newEvent = LMEvent(date: event.date, identifier: event.identifier, state: event.state)
                context.insert(newEvent)
                try context.save()
            }
        }
    }
    
    func updateRecords() async {
        UIRows = [:]
        for identifier in await monitor?.identifiers ?? [] {
            guard let lastEvent = await monitor!.record(for: identifier)?.lastEvent else { continue }
            UIRows[identifier] = [lastEvent]
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) var ModelContext
    @ObservedObject fileprivate var locationMonitor = ObservableMonitorModel.shared
    @Query(sort: [SortDescriptor(\LMEvent.date)]) var lmevents: [LMEvent]
    
    var body: some View {
        if locationMonitor.authSessionActive {
            if locationMonitor.lastDiagnosticUpdate?.authorizationDeniedGlobally ?? false {
                ErrorView(errorMessage: globalAuthDeniedError)
            } else if locationMonitor.lastDiagnosticUpdate?.authorizationDenied ?? false {
                ErrorView(errorMessage: authDeniedError)
            } else if locationMonitor.lastDiagnosticUpdate?.authorizationRestricted ?? false {
                ErrorView(errorMessage: authRestrictedError)
            } else if locationMonitor.lastDiagnosticUpdate?.insufficientlyInUse ?? false {
                EmptyView()
            } else if locationMonitor.lastDiagnosticUpdate?.fullAccuracyDenied ?? false {
                ErrorView(errorMessage: accuracyLimitedError)
            } else if locationMonitor.lastDiagnosticUpdate?.alwaysAuthorizationDenied ?? false {
                ErrorView(errorMessage: alwaysAuthDeniedError)
            }
        } else {
            ErrorView(errorMessage: sessionInactiveError)
        }
        
        VStack {
                if lmevents.count > 0 {
                    List(lmevents) {
                        eve in
                        HStack {
                            Text("\(eve.identifier ?? "")")
                            Text("EV: \(String(describing: eve.date)) \(eve.state?.description ?? "")")
                        }
                    }
                } else {
                    Text("No events")
                }
            Spacer()
//            ScrollView {
//                VStack {
//                    ForEach(locationMonitor.UIRows.keys.sorted(), id: \.self) {condition in
//                        HStack(alignment: .top) {
//                            Button(action: {
//                                Task {
//                                    await locationMonitor.monitor?.remove(condition)
//                                    await locationMonitor.updateRecords()
//                                }
//                            }) {
//                                Image(systemName: "xmark.circle")
//                            }
//                            Text(condition)
//                            ScrollViewReader {reader in
//                                ScrollView {
//                                    VStack {
//                                        ForEach((locationMonitor.UIRows[condition] ?? []).indices, id: \.self) {index in
//                                            HStack {
//                                                switch locationMonitor.UIRows[condition]![index].state {
//                                                case .satisfied: Text("Satisfied")
//                                                case .unsatisfied: Text("Unsatisfied")
//                                                case .unknown: Text("Unknown")
//                                                case .unmonitored: Text("Unmonitored")
//                                                @unknown default:
//                                                    fatalError()
//                                                }
//                                                Text(locationMonitor.UIRows[condition]![index].date, style: .time)
//                                            }
//                                        }
//                                        Text("")
//                                            .frame(height: 5)
//                                            .id("lastElement")
//                                    }
//                                }
//                                .frame(height: 40)
//                                .onChange(of: locationMonitor.UIRows[condition]?.count) {
//                                    reader.scrollTo("lastElement")
//                                    Task {
//                                        sleep(1)
//                                        withAnimation(.easeInOut(duration: 3)) {
//                                            reader.scrollTo(0)
//                                        }
//                                    }
//                                }
//                            }
//                        }
//                    }
//                    .padding(20)
//                }
//            }
        }
        Divider()
        .padding(25)
        Toggle("Location Service Session:", isOn: $locationMonitor.authSessionActive)
        .frame(width: 265)
        .padding(20)
        Button("Add CircularGeographicCondition") {
            Task {
                await locationMonitor.monitor?.add(getCircularGeographicCondition(), identifier: "ApplePark")
                await locationMonitor.updateRecords()
            }
        }
        .padding(20)
        .border(.gray)
        Button("Add BeaconIdentityCondition") {
            Task {
                await locationMonitor.monitor?.add(getBeaconIdentityCondition(), identifier: "TestBeacon")
                await locationMonitor.updateRecords()
            }
        }
        .padding(20)
        .border(.gray)
        Spacer()
        .frame(height: 100)
    }
}

func getCircularGeographicCondition() -> CLMonitor.CircularGeographicCondition {
    return CLMonitor.CircularGeographicCondition(
        center: appleParkLocation,
        radius: 50)
}

func getBeaconIdentityCondition() -> CLMonitor.BeaconIdentityCondition {
    CLMonitor.BeaconIdentityCondition(uuid: testBeaconId)
}

struct ErrorView: View {
    @State var errorMessage: String
    
    var body: some View {
        GroupBox {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .frame(width: 50, height: 50)
                Text(errorMessage)
            }
        }
        .padding(20)
        .cornerRadius(1)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
