import Foundation

// Spinel lives in libSpinelKit.dylib so Quarry can load the very same build. Run on its own, this
// launcher loads the library and hands over to it.
let name = "libSpinelKit.dylib"
let candidates = [
    Bundle.main.privateFrameworksURL?.appendingPathComponent(name),  // Spinel.app/Contents/Frameworks
    Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),  // .build/<config>
].compactMap { $0 }

guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })?.path,
      let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
      let entry = dlsym(handle, "spinel_main")
else {
    FileHandle.standardError.write(Data("Spinel: couldn't load \(name): \(dlerror().map { String(cString: $0) } ?? "not found")\n".utf8))
    exit(1)
}
unsafeBitCast(entry, to: (@convention(c) () -> Void).self)()
