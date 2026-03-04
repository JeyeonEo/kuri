import Foundation

public enum StoreEnvironment {
    public static func makeRepository(baseDirectory: URL) throws -> SQLiteCaptureRepository {
        let databaseURL = baseDirectory.appendingPathComponent("kuri.sqlite")
        let imageDirectory = baseDirectory.appendingPathComponent("images", isDirectory: true)
        return try SQLiteCaptureRepository(databaseURL: databaseURL, imageDirectory: imageDirectory)
    }
}
