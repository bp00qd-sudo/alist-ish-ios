import SwiftUI
import UIKit

@objc(AlistHostFactory)
public final class AlistHostFactory: NSObject {
    @MainActor @objc public static func makeRootViewController() -> UIViewController {
        let model = AppModel()
        return UIHostingController(rootView: ContentView().environmentObject(model))
    }
}
