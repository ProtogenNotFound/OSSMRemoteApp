import Combine

@MainActor
final class OSSMNavigationPath: ObservableObject {
    @Published var path: [OSSMPage]

    init(path: [OSSMPage] = []) {
        self.path = path
    }
}
