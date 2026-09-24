import SwiftUI
import UIKit

@objc(AlistHostFactory)
final class AlistHostFactory: NSObject {
    @objc static func makeRootViewController() -> UIViewController {
        let model = AppModel()
        return UIHostingController(rootView: ContentView().environmentObject(model))
    }
}
