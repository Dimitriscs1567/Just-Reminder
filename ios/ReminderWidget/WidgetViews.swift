import SwiftUI
import WidgetKit

/// Widget colors (Product decisions → Look, the approved mockup), the same
/// as the Android widget's res/values*/colors.xml. A due reminder is always
/// teal; missed and paused are neutral; nothing due is the quiet default
/// background (iOS widgets can't be translucent).
enum Palette {
  static func firingTile(_ scheme: ColorScheme) -> Color { pick(scheme, 0xD5F5EE, 0x113F3A) }
  static func onFiring(_ scheme: ColorScheme) -> Color { pick(scheme, 0x04342C, 0xB4F2E6) }
  static func onFiringVariant(_ scheme: ColorScheme) -> Color { pick(scheme, 0x085041, 0x9ADFD1) }
  static func due(_ scheme: ColorScheme) -> Color { pick(scheme, 0x0F766E, 0x2DD4BF) }
  static func neutralTile(_ scheme: ColorScheme) -> Color { pick(scheme, 0xF3EDF7, 0x2B2930) }
  static func onNeutral(_ scheme: ColorScheme) -> Color { pick(scheme, 0x1D1B20, 0xE6E0E9) }
  static func neutralVariant(_ scheme: ColorScheme) -> Color { pick(scheme, 0x5F5E5A, 0xCAC4D0) }
  static func outline(_ scheme: ColorScheme) -> Color { pick(scheme, 0x888780, 0x938F99) }
  static func doneTile(_ scheme: ColorScheme) -> Color { pick(scheme, 0xFFFFFF, 0x1C1C1E) }
  static func onDone(_ scheme: ColorScheme) -> Color { pick(scheme, 0x1F1F1F, 0xF2F2F2) }
  static let bubble = Color(rgb: 0x5F5E5A)

  /// The one-reminder widget's background.
  static func tile(_ state: WidgetStore.State, _ scheme: ColorScheme) -> Color {
    switch state {
    case .firing: return firingTile(scheme)
    case .done: return doneTile(scheme)
    default: return neutralTile(scheme)
    }
  }

  /// Text on `tile(state)`.
  static func onTile(_ state: WidgetStore.State, _ scheme: ColorScheme) -> Color {
    switch state {
    case .firing: return onFiring(scheme)
    case .done: return onDone(scheme)
    default: return onNeutral(scheme)
    }
  }

  private static func pick(_ scheme: ColorScheme, _ light: UInt32, _ dark: UInt32) -> Color {
    Color(rgb: scheme == .dark ? dark : light)
  }
}

extension Color {
  init(rgb: UInt32) {
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}

/// A reminder's state at a glance, like the app's StatusIcon: a teal ring
/// with a thumbs-up (due), a gray dashed ring with a thumbs-up crossed by a
/// dashed line (missed), a check (nothing due), a pause sign (paused).
struct StateIcon: View {
  let state: WidgetStore.State
  let size: CGFloat
  /// The color behind the icon: the missed sign's slash is cut out of the
  /// thumb with it.
  let surface: Color
  /// The check's color (it sits on different backgrounds).
  let checkColor: Color

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let due = Palette.due(colorScheme)
    let faint = Palette.outline(colorScheme)
    let stroke = max(2, size * 0.083)
    Group {
      switch state {
      case .firing:
        ZStack {
          Circle().inset(by: stroke / 2).stroke(due, lineWidth: stroke)
          Image(systemName: "hand.thumbsup.fill")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(due)
        }
      case .missed:
        let dashedStroke = max(1.5, size * 0.073)
        let circumference = CGFloat.pi * (size - dashedStroke)
        ZStack {
          Circle()
            .inset(by: dashedStroke / 2)
            .stroke(
              faint,
              style: StrokeStyle(
                lineWidth: dashedStroke,
                lineCap: .round,
                dash: [circumference / 28, circumference / 28]
              )
            )
            .rotationEffect(.degrees(-90))
          Image(systemName: "hand.thumbsup")
            .font(.system(size: size * 0.36, weight: .medium))
            .foregroundStyle(faint)
          // The slash, on a gap in the background color.
          Slash().stroke(surface, style: StrokeStyle(lineWidth: dashedStroke * 0.8 * 2.2, lineCap: .round))
          Slash().stroke(
            faint,
            style: StrokeStyle(
              lineWidth: dashedStroke * 0.8,
              lineCap: .round,
              dash: [Slash.length(in: size) / 7, Slash.length(in: size) / 7]
            )
          )
        }
      case .done:
        Image(systemName: "checkmark")
          .font(.system(size: size * 0.45, weight: .semibold))
          .foregroundStyle(checkColor)
      case .paused:
        Image(systemName: "pause.fill")
          .font(.system(size: size * 0.4, weight: .semibold))
          .foregroundStyle(faint)
      case .archived, .deleted:
        Color.clear
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel(label)
  }

  private var label: String {
    switch state {
    case .firing: return "Due. Mark it done"
    case .missed: return "Missed"
    case .paused: return "Paused"
    default: return "Nothing due"
    }
  }
}

/// A line from bottom left to top right (the missed sign's slash).
struct Slash: Shape {
  static func reach(in size: CGFloat) -> CGFloat { size * 0.3 }
  static func length(in size: CGFloat) -> CGFloat { reach(in: size) * 2 * CGFloat(2).squareRoot() }

  func path(in rect: CGRect) -> Path {
    let reach = Slash.reach(in: min(rect.width, rect.height))
    var path = Path()
    path.move(to: CGPoint(x: rect.midX - reach, y: rect.midY + reach))
    path.addLine(to: CGPoint(x: rect.midX + reach, y: rect.midY - reach))
    return path
  }
}

/// The day's missed count: a neutral bubble, never red.
struct MissedBubble: View {
  let count: Int

  var body: some View {
    Text(count > 99 ? "99+" : "\(count)")
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 5)
      .frame(minWidth: 18, minHeight: 18)
      .background(Capsule().fill(Palette.bubble))
      .accessibilityLabel("\(count) missed")
  }
}

/// A list row's status, as on Android: "Due · 1 missed", "Missed · 2",
/// "Done", "Paused", "Archived", "Deleted".
func statusText(_ state: WidgetStore.State) -> String {
  let missed = state.missedCount
  switch state {
  case .firing: return missed > 0 ? "Due · \(missed) missed" : "Due"
  case .missed: return missed > 0 ? "Missed · \(missed)" : "Missed"
  case .done: return missed > 0 ? "Done · \(missed) missed" : "Done"
  case .paused: return missed > 0 ? "Paused · \(missed) missed" : "Paused"
  case .archived: return "Archived"
  case .deleted: return "Deleted"
  }
}

/// Taps that open the app (`appEventForWidgetUri` in Dart). The
/// `homeWidget` parameter lets home_widget recognize widget links.
enum WidgetLinks {
  static func reminder(_ reminderId: String) -> URL? {
    let id = reminderId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reminderId
    return URL(string: "justreminder://reminder/\(id)?homeWidget")
  }

  /// For an archived or deleted reminder: the app explains Edit Widget.
  static let help = URL(string: "justreminder://widget-help?homeWidget")
}
