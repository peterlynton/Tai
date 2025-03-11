import SwiftUI

struct CustomDateTimePicker: UIViewRepresentable {
    @Binding var selection: Date
    var minuteInterval: Int

    class Coordinator: NSObject {
        var parent: CustomDateTimePicker

        init(_ parent: CustomDateTimePicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .dateAndTime
        datePicker.minuteInterval = minuteInterval
        datePicker.maximumDate = Date()
        datePicker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
        return datePicker
    }

    func updateUIView(_ uiView: UIDatePicker, context _: Context) {
        uiView.date = selection
        uiView.minuteInterval = minuteInterval
        uiView.maximumDate = Date()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
