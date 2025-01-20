import SwiftUI
import AppKit
import HierarchyStringParser

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
    @State private var path: [Int] = [] // For navigation history
    
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
    
    @State private var rotation: Double = 0.0
    @State private var hoveredIndex: Int?
    @State private var normalizedRadius: Double = 0.4  // Track radius in normalized space
    @State private var isPinching: Bool = false
    @State private var lastPinchScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
            
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
                    rotation: rotation
                ) {
                    onTap(element)
                } onHover: { isHovered in
                    hoveredIndex = isHovered ? index : nil
                }
            }
        }
        .gesture(
            RotationGesture()
                .onChanged { angle in
                    rotation = angle.degrees
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
                    if abs(newRadius) < 0.05 && 
                       normalizedRadius.sign != newRadius.sign {
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

struct RadialLabel: View {
    let text: String
    let index: Int
    let totalCount: Int
    let normalizedRadius: Double
    let center: CGPoint
    let isHovered: Bool
    let rotation: Double
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    
    private var normalizedPosition: CGPoint {
        let angleBetweenLabels = 360.0 / Double(totalCount)
        let baseAngle = 180.0 + 
            (-1 * angleBetweenLabels) + 
            (Double(index) * angleBetweenLabels) 
        let radAngle = baseAngle * .pi / 180.0

        // Calculate base position
        let xVal = cos(radAngle) * normalizedRadius
        let yVal = sin(radAngle) * normalizedRadius

        // Apply aspect ratio correction to maintain circular shape
        let aspectRatio = center.x / center.y
        let adjustedYVal = yVal * aspectRatio

        return CGPoint(x: xVal, y: adjustedYVal)
    }
    
    private var screenPosition: CGPoint {
        CGPoint(
            x: center.x * (1 + normalizedPosition.x * 2),
            y: center.y * (1 + normalizedPosition.y * 2)
        )
    }
    
    private var opacity: Double {
        // Fade based on normalized radius
        if abs(normalizedRadius) < 0.1 {
            return 0
        } else if abs(normalizedRadius) < 0.2 {
            return (abs(normalizedRadius) - 0.1) * 10 // Linear fade from 0.1 to 0.2
        }
        return 1
    }
    
    private var scale: Double {
        // Scale based on normalized radius
        let baseScale = min(1.4, max(0.4, abs(normalizedRadius) / 0.4))
        return isHovered ? baseScale * 1.2 : baseScale
    }
    
	private var labelRotation: Double {
	    // Since we're in centered coordinates, rotation should be based on 
	    // position in normalized space without the additional transformations
	    let angle = atan2(normalizedPosition.y, normalizedPosition.x) * 180 / .pi
	    return angle  
	}
    
    var body: some View {
	    Text("\(text) (\(Int(labelRotation))°)")
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