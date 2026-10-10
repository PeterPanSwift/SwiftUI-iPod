import SwiftUI

struct ContentView: View {
    @State private var model = IPodModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        IPodView(model: model)
            .background {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(white: 0.2), Color(white: 0.07)]
                        : [Color(white: 0.97), Color(white: 0.82)],
                    startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }
            .task { await model.load() }
    }
}

#Preview {
    ContentView()
}
