import Foundation

enum KeyboardShortcut: Equatable {
    case space, n, p, e, t, escape, leftArrow, rightArrow

    init?(keyCode: UInt16, textFocused: Bool) {
        guard !textFocused || keyCode == 53 else { return nil }
        switch keyCode {
        case 49: self = .space
        case 45: self = .n
        case 35: self = .p
        case 14: self = .e
        case 17: self = .t
        case 53: self = .escape
        case 123: self = .leftArrow
        case 124: self = .rightArrow
        default: return nil
        }
    }
}
