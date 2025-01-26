import AppKit
import HierarchyStringParser
import SwiftUI

enum LabelAlignment {
  case leading, centered, trailing
  var offsetMultiplier: Double {
    switch self {
    case .leading: return 1
    case .centered: return 0
    case .trailing: return -1
    }
  }
}

// Coordinate conversion helpers
extension CGPoint {
  static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }

  // Convert from screen coordinates to normalized coordinates (-1...1, centered at 0,0)
  func screenToNormal(size: CGSize) -> CGPoint {
    let safeWidth = max(size.width, 1)  // Prevents division by zero
    let safeHeight = max(size.height, 1)
    return CGPoint(
      x: (x - safeWidth / 2) / (safeWidth / 2),
      y: (y - safeHeight / 2) / (safeHeight / 2)
    )
  }

  // Convert from normalized coordinates (-1...1, centered at 0,0) to screen coordinates
  func normalToScreen(size: CGSize) -> CGPoint {
    let safeWidth = max(size.width, 1)
    let safeHeight = max(size.height, 1)
    return CGPoint(
      x: x * (safeWidth / 2) + safeWidth / 2,
      y: y * (safeHeight / 2) + safeHeight / 2
    )
  }
}

extension CGSize {
  var center: CGPoint {
    CGPoint(x: width / 2, y: height / 2)
  }
}

let hierarchyString = loadHierarchyString(from: "hierarchy.txt") ?? ""

// Create Menu
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenuItem.submenu = appMenu
let quitMenuItem = NSMenuItem(
  title: "Quit",
  action: #selector(NSApplication.terminate),
  keyEquivalent: "q"
)
appMenu.addItem(quitMenuItem)

class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

  func applicationDidFinishLaunching(_ notification: Notification) {
    let contentView = ContentView(hierarchyElements: parseHierarchyString(hierarchyString))

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Radial Hierarchy Viewer"
    window.contentView = NSHostingView(rootView: contentView)
    window.center()

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}

struct AlignmentControls: View {
  @Binding var alignment: LabelAlignment

  var body: some View {
    Group {
      VStack {
        Text("Alignment")
          .font(.headline)
        HStack {
          ForEach([LabelAlignment.leading, .centered, .trailing], id: \.self) { align in
            Button(action: { alignment = align }) {
              Text(align == .leading ? "leading" : align == .centered ? "centered" : "trailing")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .fontWeight(alignment == align ? .bold : .regular)
            }
            .buttonStyle(.bordered)
            .tint(alignment == align ? .blue : .gray)
          }
        }
      }
      .padding(.bottom)
    }
    .zIndex(1)
  }
}

struct ContentView: View {
  let hierarchyElements: [HierarchyElement]
  @State private var selectedIndex: Int = -1
  @State private var path: [Int] = []  // For navigation history

  var body: some View {
    VStack {
      // Breadcrumb navigation
      HStack {
        ForEach(path + [selectedIndex], id: \.self) { index in
          if index >= 0 {
            Text(hierarchyElements[index].caption)
              .onTapGesture {
                navigateToIndex(index)
              }
            Text(">")
          }
        }
      }
      .padding()

      RadialLabelsView(
        elements: hierarchyElements.childrenOfIndex(selectedIndex),
        onTap: { element in
          if selectedIndex >= 0 {
            path.append(selectedIndex)
          }
          selectedIndex = element.index
        }
      )

      if selectedIndex != -1 {
        Button("Back") {
          selectedIndex = path.popLast() ?? -1
        }
        .padding()
      }
    }
    .frame(minWidth: 600, minHeight: 400)
  }

  private func navigateToIndex(_ index: Int) {
    if let pathIndex = path.firstIndex(of: index) {
      path.removeSubrange(pathIndex...)
      selectedIndex = index
    }
  }
}

struct CircleView: View {
  let center: CGPoint
  let radius: CGFloat
  var body: some View {
    Canvas { context, _ in
      context.stroke(
        Path { path in
          path.addArc(
            center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360),
            clockwise: true)
        },
        with: .color(.blue),
        lineWidth: 3
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

public func clampedScaleForRadius(_ radius: Double) -> Double {
  let safeRadius = max(abs(radius), 0.01)  // Avoid division by zero
  return min(2.0, max(0.4, safeRadius / 0.4))
}

struct RadialLabelsView: View {
  let elements: [HierarchyElement]
  let onTap: (HierarchyElement) -> Void

  let labelsAngle: Double = 0.0  // Fixed angle for all labels
  @State private var rotation: Double = 0.0  // For whole view rotation
  @State private var hoveredIndex: Int?
  @State private var normalizedRadius: Double = 0.4
  @State private var isPinching: Bool = false
  @State private var lastPinchScale: CGFloat = 1.0
  @State private var lastDragLocation: CGPoint?
  @State private var alignment: LabelAlignment = .leading

  private var scale: Double {
    return clampedScaleForRadius(normalizedRadius)
  }

  var body: some View {

    VStack {
      AlignmentControls(alignment: $alignment)
      GeometryReader { geometry in
        let center = geometry.size.center
        CircleView(center: center, radius: abs(normalizedRadius) * geometry.size.width / 2.0)
          .scaleEffect(scale)
        ZStack {
          // Center indicator
          Circle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: 20, height: 20)
            .position(center)

          // Labels
          ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
            RadialLabel(
              text: element.caption,
              index: index,
              totalCount: elements.count,
              normalizedRadius: normalizedRadius,
              center: center,
              isHovered: hoveredIndex == index,
              labelsAngle: labelsAngle,
              alignmentMultiplier: alignment.offsetMultiplier
            ) {
              onTap(element)
            } onHover: { isHovered in
              hoveredIndex = isHovered ? index : nil
            }
          }
        }
        .rotationEffect(.degrees(rotation))
        .gesture(
          DragGesture()
            .onChanged { value in
              // Convert to normalized space centered at 0,0
              let currentNorm = value.location.screenToNormal(size: geometry.size)

              if lastDragLocation == nil {
                lastDragLocation = value.startLocation
              }

              // Previous position in normalized space
              let previousNorm = lastDragLocation!.screenToNormal(size: geometry.size)
              lastDragLocation = value.location

              // We're already in normalized space relative to center (0,0)
              let currentVector = currentNorm
              let prevVector = previousNorm

              // Calculate angle between vectors
              let dot = Double(prevVector.x * currentVector.x + prevVector.y * currentVector.y)
              let det = Double(prevVector.x * currentVector.y - prevVector.y * currentVector.x)

              let safeDot = dot == 0 && det == 0 ? 1.0 : dot  // Prevent undefined atan2(0,0)
              let angleDelta = atan2(det, safeDot) * 180 / Double.pi
              rotation += angleDelta
            }
            .onEnded { _ in
              lastDragLocation = nil
            }
        )
        .gesture(
          MagnificationGesture()
            .onChanged { scale in
              if !isPinching {
                isPinching = true
                lastPinchScale = scale
              }

              let safeLastPinchScale = max(lastPinchScale, 0.01)  // Prevents division by zero
              let delta = scale / safeLastPinchScale
              lastPinchScale = scale

              // Update radius in normalized space
              let newRadius = normalizedRadius * delta

              // Allow inversion through center
              if abs(newRadius) < 0.05 && normalizedRadius.sign != newRadius.sign {
                normalizedRadius = -normalizedRadius
              } else {
                normalizedRadius = newRadius.clamped(to: -0.8...0.8)
              }
            }
            .onEnded { _ in
              isPinching = false

              // Animate to stable radius if very small
              if abs(normalizedRadius) < 0.1 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                  normalizedRadius = normalizedRadius.sign == .minus ? -0.2 : 0.2
                }
              }
            }
        )
      }
    }
  }
}

struct RadialLabel: View {
  let text: String
  let index: Int
  let totalCount: Int
  let normalizedRadius: Double
  let center: CGPoint
  let isHovered: Bool
  let labelsAngle: Double
  let alignmentMultiplier: Double
  let onTap: () -> Void
  let onHover: (Bool) -> Void

  @State private var labelWidth: CGFloat = 0

  private var normalizedPosition: CGPoint {
    let angleBetweenLabels = 360.0 / Double(totalCount)
    let baseAngle = 180.0 + (-1 * angleBetweenLabels) + (Double(index) * angleBetweenLabels)
    let radAngle = baseAngle * Double.pi / 180.0

    let widthOffset = (labelWidth / 2) / center.x * alignmentMultiplier
    let adjustedRadius = normalizedRadius + Double(widthOffset)

    // Calculate position in -1...1 range
    let xVal = cos(radAngle) * adjustedRadius
    let yVal = sin(radAngle) * adjustedRadius

    return CGPoint(x: xVal, y: yVal)
  }

  private var screenPosition: CGPoint {
    // Apply aspect ratio correction to maintain circular shape
    let safeCenterY = max(center.y, 1)  // Prevents division by zero
    let aspectRatio = center.x / safeCenterY
    let adjustedNormPos = CGPoint(x: normalizedPosition.x, y: normalizedPosition.y * aspectRatio)
    return adjustedNormPos.normalToScreen(
      size: CGSize(width: center.x * 2, height: safeCenterY * 2))
  }

  private var opacity: Double {
    if abs(normalizedRadius) < 0.1 {
      return 0
    } else if abs(normalizedRadius) < 0.2 {
      return (abs(normalizedRadius) - 0.1) * 10
    }
    return 1
  }

  private var scale: Double {
    return clampedScaleForRadius(normalizedRadius)
  }

  private var labelRotation: Double {
    let baseAngle = atan2(normalizedPosition.y, normalizedPosition.x) * 180 / Double.pi
    return baseAngle + labelsAngle
  }

  var body: some View {
    Text(text.trimmingCharacters(in: .whitespaces))
      .font(.system(size: 14))
      .padding(4)
      .background(
        RoundedRectangle(cornerRadius: 5)
          .fill(isHovered ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
      )
      .overlay {
        GeometryReader { geo in
          Color.clear  // Use clear color to get size without visible overlay
            .onAppear {
              labelWidth = geo.size.width
            }
        }
      }
      .rotationEffect(.degrees(labelRotation))
      .position(screenPosition)
      .scaleEffect(scale)
      .opacity(opacity)
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scale)
      .animation(.easeOut(duration: 0.2), value: opacity)
      .onHover { hovering in
        onHover(hovering)
      }
      .onTapGesture(perform: onTap)
  }
}

// Helper for clamping values
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

func loadHierarchyString(from path: String) -> String? {
  guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
    print("Error: Could not load hierarchy file at \(path)")
    return nil
  }
  return contents
}

// Initialize the application
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Set up the app menu
app.mainMenu = mainMenu

// Set up the delegate
let delegate = AppDelegate()
app.delegate = delegate

// Run the application
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
