import AppKit

/// Plays the attention effect on menu bar items whose badge just appeared or went up.
///
/// An effect runs a few short cycles and then stops: the menu bar is always on screen, so
/// motion that never ends would only be distracting. With repeating on, it plays one cycle
/// every few seconds for as long as the badge stays.
///
/// Kept cheap in three ways:
/// - each frame is drawn once into a small bitmap and replayed on later cycles;
/// - repeating items share one clock, so they animate together and the app wakes once per
///   cycle rather than once per item;
/// - the timer only runs while a cycle is playing, and sleeps until the next one otherwise.
@MainActor
final class BadgeEffects {
    private struct Entry {
        var badge: Badge?
        /// Identifies what the item looks like; frames are redrawn when it changes.
        var look: AnyHashable?
        var render: ((BadgeEffect, CGFloat) -> NSImage)?
        /// When a one-off burst started, while it's playing.
        var burstStart: Date?
        /// Frames drawn so far, by index. `plainFrame` is the image without an effect.
        var frames: [Int: NSImage] = [:]
        /// What the frames were drawn for: the effect and the menu bar's appearance.
        var framesFor: String?
        /// The frame on screen, so unchanged frames aren't sent again.
        var shown: Int?
    }

    var effect: BadgeEffect = .off
    var repeats = false
    /// Off for the first rebuild, so badges that were already there at launch don't all play.
    var isReady = false

    private static let cycle: TimeInterval = 0.8
    private static let burstCycles = 3.0
    private static let repeatEvery: TimeInterval = 6
    private static let framesPerSecond = 24.0
    private static let framesPerCycle = Int(cycle * framesPerSecond)
    private static let plainFrame = -1

    private var entries: [String: Entry] = [:]
    private var timer: Timer?
    /// The shared clock repeating effects run on.
    private let epoch = Date()
    private let draw: (String, NSImage) -> Void
    private let appearance: (String) -> NSAppearance?

    /// - Parameters:
    ///   - draw: puts a frame on the item with the given key.
    ///   - appearance: the appearance the item is drawn in, so frames match the menu bar.
    init(draw: @escaping (String, NSImage) -> Void, appearance: @escaping (String) -> NSAppearance?) {
        self.draw = draw
        self.appearance = appearance
    }

    /// Records an item's current badge, starting its effect if the badge is new or went up.
    func update(key: String, badge: Badge?, look: AnyHashable?, render: ((BadgeEffect, CGFloat) -> NSImage)?) {
        var entry = entries[key] ?? Entry()
        let old = entry.badge
        entry.badge = badge
        entry.render = render
        if entry.look != look {
            entry.look = look
            entry.frames = [:]
            entry.shown = nil
        }
        if badge == nil || resolvedEffect == .off {
            entry.burstStart = nil
        } else if isReady, Self.isNews(badge, after: old) {
            entry.burstStart = Date()
        }
        entries[key] = entry
        // Something about it changed while it's animating; show the right frame right away
        // instead of waiting for the timer, which may be asleep between cycles.
        if isAnimating(key) { show(key, at: Date()) }
        schedule()
    }

    func remove(key: String) {
        entries[key] = nil
    }

    /// Forgets which frame is on screen, so the next update draws it again. Used when an item
    /// moves to another menu bar slot, which still shows the previous item's image.
    func redraw(key: String) {
        entries[key]?.shown = nil
    }

    /// Whether this class draws the item's image, rather than the caller.
    func isAnimating(_ key: String) -> Bool {
        guard let entry = entries[key], entry.badge != nil, resolvedEffect != .off else { return false }
        return entry.burstStart != nil || repeats
    }

    private static func isNews(_ badge: Badge?, after old: Badge?) -> Bool {
        guard let badge else { return false }
        guard let old else { return true }
        if let count = badge.count, let oldCount = old.count { return count > oldCount }
        return badge.count != nil && old.count == nil
    }

    /// Movement is swapped for the glow, which only changes opacity, when Reduce Motion is on.
    private var resolvedEffect: BadgeEffect {
        guard effect != .off, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return effect }
        return .glow
    }

    // MARK: - Frames

    /// The frame an item should show now, and how long until its next cycle if it's resting.
    private func position(of entry: inout Entry, at now: Date) -> (frame: Int, wait: TimeInterval?) {
        if let start = entry.burstStart {
            let elapsed = now.timeIntervalSince(start)
            if elapsed < Self.cycle * Self.burstCycles {
                return (Self.frameIndex(elapsed), nil)
            }
            entry.burstStart = nil
            // Without repeating, the frames won't be needed again until the next burst.
            if !repeats { entry.frames = [:] }
        }
        guard repeats, entry.badge != nil else { return (Self.plainFrame, nil) }
        let local = now.timeIntervalSince(epoch).truncatingRemainder(dividingBy: Self.repeatEvery)
        if local < Self.cycle { return (Self.frameIndex(local), nil) }
        return (Self.plainFrame, Self.repeatEvery - local)
    }

    private static func frameIndex(_ elapsed: TimeInterval) -> Int {
        let progress = elapsed.truncatingRemainder(dividingBy: cycle) / cycle
        return min(Int(progress * Double(framesPerCycle)), framesPerCycle - 1)
    }

    /// Puts the right frame on an item, drawing it first if this is its first use.
    private func show(_ key: String, at now: Date) {
        guard var entry = entries[key], let render = entry.render else { return }
        let effect = resolvedEffect
        let appearance = appearance(key)
        let framesFor = "\(effect.rawValue)|\(appearance?.name.rawValue ?? "")"
        if entry.framesFor != framesFor {
            entry.framesFor = framesFor
            entry.frames = [:]
            entry.shown = nil
        }

        let (frame, _) = position(of: &entry, at: now)
        if entry.shown != frame {
            let image = entry.frames[frame] ?? BadgeRenderer.bitmap(in: appearance) {
                frame == Self.plainFrame
                    ? render(.off, 0)
                    : render(effect, CGFloat(frame) / CGFloat(Self.framesPerCycle))
            }
            entry.frames[frame] = image
            entry.shown = frame
            draw(key, image)
        }
        entries[key] = entry
    }

    private func tick() {
        let now = Date()
        for key in entries.keys where entries[key]?.render != nil {
            if isAnimating(key) || entries[key]?.shown != Self.plainFrame && entries[key]?.shown != nil {
                show(key, at: now)
            }
        }
        schedule()
    }

    /// Runs the frame timer while any cycle is playing, otherwise sleeps until the next one.
    private func schedule() {
        let now = Date()
        var playing = false
        var nextWait: TimeInterval?
        for key in entries.keys {
            guard var entry = entries[key], entry.render != nil else { continue }
            let (frame, wait) = position(of: &entry, at: now)
            // Still playing, or needs one more tick to settle on its plain image.
            if frame != Self.plainFrame || (entry.shown != nil && entry.shown != Self.plainFrame) {
                playing = true
            }
            if let wait { nextWait = min(nextWait ?? wait, wait) }
        }

        let interval: TimeInterval? = playing ? 1 / Self.framesPerSecond : nextWait
        guard let interval else {
            timer?.invalidate()
            timer = nil
            return
        }
        if let timer, timer.isValid, playing, timer.timeInterval == interval { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: playing) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = playing ? 0.005 : 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
