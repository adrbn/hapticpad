import Foundation

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnose") {
            exit(Diagnostics.run())
        }
        if arguments.contains("--snapshot") {
            exit(MainActor.assumeIsolated { Snapshot.run(arguments: arguments) })
        }
        HapticPadApp.main()
    }
}
