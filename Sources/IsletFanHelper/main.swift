import Foundation
import IOKit.pwr_mgt

// Dynamic Peninsula's fan helper: a launch daemon (SMAppService) that runs as root, takes fan requests from the app
// over XPC, and gives the fans back to macOS whenever anything goes wrong (`FanController`).

guard let controller = FanController() else { exit(1) }
controller.start()

final class Service: NSObject, FanHelperProtocol {
    let controller: FanController
    init(_ controller: FanController) { self.controller = controller }

    func status(reply: @escaping (NSDictionary) -> Void) {
        controller.queue.async { reply(self.controller.status()) }
    }

    func setSpeed(_ rpm: Double, reply: @escaping (Bool, String?) -> Void) {
        controller.queue.async { let r = self.controller.set(rpm); reply(r.0, r.1) }
    }

    func setFullSpeed(reply: @escaping (Bool, String?) -> Void) {
        controller.queue.async { let r = self.controller.set(nil); reply(r.0, r.1) }
    }

    func setAutomatic(reply: @escaping (Bool) -> Void) {
        controller.queue.async { self.controller.handBack(nil); reply(true) }
    }

    func heartbeat() {
        controller.queue.async { self.controller.heard() }
    }
}

final class Listener: NSObject, NSXPCListenerDelegate {
    let controller: FanController
    init(_ controller: FanController) { self.controller = controller }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = Service(controller)
        let controller = self.controller
        var counted = true
        let gone = {
            controller.queue.async {
                guard counted else { return }
                counted = false
                controller.connections -= 1
            }
        }
        connection.invalidationHandler = gone
        connection.interruptionHandler = gone
        controller.queue.sync { controller.connections += 1 }
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: FanHelperInfo.machService)
// Only Dynamic Peninsula, signed by its own team, gets in.
listener.setConnectionCodeSigningRequirement(FanHelperInfo.appRequirement)
let delegate = Listener(controller)
listener.delegate = delegate
listener.resume()

// SIGTERM (shutdown, logout, the helper being removed): give the fans back first.
signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: controller.queue)
term.setEventHandler {
    controller.handBack(nil)
    exit(0)
}
term.resume()

SleepWatch.start(controller)

RunLoop.main.run()
