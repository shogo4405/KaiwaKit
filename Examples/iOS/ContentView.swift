import SwiftUI

struct ContentView: View {
    @StateObject private var model = ContentViewModel()

    var body: some View {
        VStack {
            TextEditor(text: $model.lines)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray, lineWidth: 1)
                )
            HStack {
                Spacer()
                switch model.readyState {
                case .connecting:
                    Spacer()
                case .open:
                    Button(action: {
                        model.close()
                    }, label: {
                        Image(systemName: "stop.circle")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                    })
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
                    .cornerRadius(30.0)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 16.0, trailing: 16.0))
                case .closing:
                    Spacer()
                case .closed:
                    Button(action: {
                        model.connect()
                    }, label: {
                        Image(systemName: "record.circle")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                    })
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
                    .cornerRadius(30.0)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16.0))
                }
            }.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.startRunning()
        }
    }
}
