import AppKit
import HierarchyStringParser
import SwiftUI

// Coordinate conversion helpers
extension CGPoint {
  static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }

  func screenToNormal(size: CGSize) -> CGPoint {
    CGPoint(x: x / size.width, y: y / size.height)
  }

  func normalToScreen(size: CGSize) -> CGPoint {
    CGPoint(x: x * size.width, y: y * size.height)
  }
}

extension CGSize {
  var center: CGPoint {
    CGPoint(x: width / 2, y: height / 2)
  }
}

let hierarchyString = """
breakfast
    cheese
    eggs
        white
        brown
cats
    tabby
    alley
vegetables
    carrots
        orange
    tomatoes
        roma
        heirloom
        green
            fried
foods
    bread
        french
        wheat
        white
        rye
        oat
    cheese
        cheddar
        swiss
        american
    vegetables
        cucumber
        tomato
        potato
states
    florida
        activities
            swimming
            running
            being weird
        counties
            hernando
            pinellas
    minnesota
        activities
            freezing
            being cold
            fishing
                lake
                    walleye
                    musky
                river
                    bass
        counties
            aitkin
            carlton
colors
    red
        apples
        cherries
    green
    blue
    purple
"""


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

  var body: some View {
    GeometryReader { geometry in
      let center = geometry.size.center

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
            labelsAngle: labelsAngle
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
            let currentNorm = value.location.screenToNormal(size: geometry.size)
            let centerNorm = CGPoint(x: 0.5, y: 0.5)

            if lastDragLocation == nil {
              lastDragLocation = value.startLocation
            }

            let previousNorm = lastDragLocation!.screenToNormal(size: geometry.size)
            lastDragLocation = value.location

            // Get vectors relative to center in normalized space
            let currentVector = CGPoint(
              x: currentNorm.x - centerNorm.x, y: currentNorm.y - centerNorm.y)
            let prevVector = CGPoint(
              x: previousNorm.x - centerNorm.x, y: previousNorm.y - centerNorm.y)

            // Calculate angle between vectors
            let dot = Double(prevVector.x * currentVector.x + prevVector.y * currentVector.y)
            let det = Double(prevVector.x * currentVector.y - prevVector.y * currentVector.x)

            let angleDelta = atan2(det, dot) * 180 / Double.pi
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

            let delta = scale / lastPinchScale
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

struct RadialLabel: View {
  let text: String
  let index: Int
  let totalCount: Int
  let normalizedRadius: Double
  let center: CGPoint
  let isHovered: Bool
  let labelsAngle: Double
  let onTap: () -> Void
  let onHover: (Bool) -> Void

  private var normalizedPosition: CGPoint {
    let angleBetweenLabels = 360.0 / Double(totalCount)
    let baseAngle = 180.0 + (-1 * angleBetweenLabels) + (Double(index) * angleBetweenLabels)

    let radAngle = baseAngle * Double.pi / 180.0

    // Calculate base position
    let xVal = cos(radAngle) * normalizedRadius
    let yVal = sin(radAngle) * normalizedRadius

    // Apply aspect ratio correction to maintain circular shape
    let aspectRatio = center.x / center.y
    let adjustedYVal = yVal * aspectRatio

    return CGPoint(x: xVal, y: adjustedYVal)
  }

  private var screenPosition: CGPoint {
    let normalPosition = CGPoint(
      x: normalizedPosition.x + 0.5,
      y: normalizedPosition.y + 0.5
    )
    return normalPosition.normalToScreen(size: CGSize(width: center.x * 2, height: center.y * 2))
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
    let baseScale = min(1.4, max(0.4, abs(normalizedRadius) / 0.4))
    return isHovered ? baseScale * 1.2 : baseScale
  }

  private var labelRotation: Double {
    let baseAngle = atan2(normalizedPosition.y, normalizedPosition.x) * 180 / Double.pi
    return baseAngle + labelsAngle
  }

  var body: some View {
    Text(text)
      .font(.system(size: 14))
      .padding(8)
      .background(
        RoundedRectangle(cornerRadius: 5)
          .fill(isHovered ? Color.blue.opacity(0.2) : Color.clear)
      )
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
