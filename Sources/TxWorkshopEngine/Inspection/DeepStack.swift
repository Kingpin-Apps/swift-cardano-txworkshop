import Foundation

/// Runs deeply recursive work on a thread with a large stack.
///
/// Swift concurrency's threads have small stacks, and a recursive walk of
/// deeply nested data can overflow them. This gives such work room.
enum DeepStack {
    static let stackSize = 256 * 1024 * 1024

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: work())
            }
            thread.stackSize = stackSize
            thread.start()
        }
    }
}
