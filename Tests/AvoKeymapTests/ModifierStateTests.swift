import AvoKeymap
import Testing

/// A modifier's state comes from each flags-changed event, never from
/// counting the changes (a change another window took left a view's count
/// backwards: Shift to run walked while held).
@Suite("Modifier keys")
struct ModifierStateTests {
    // NSEvent.ModifierFlags as AppKit sends them: the modifier as a whole, plus each side's device bit.
    let shift: UInt = 1 << 17, control: UInt = 1 << 18, option: UInt = 1 << 19, command: UInt = 1 << 20, capsLock: UInt = 1 << 16
    let leftShift: UInt = 0x02, rightShift: UInt = 0x04, leftOption: UInt = 0x20, rightCommand: UInt = 0x10

    @Test("Shift is down while its flags say so, whatever came before")
    func shiftFollowsTheFlags() {
        #expect(KeyboardMapping.isModifierDown(.shift, flags: shift | leftShift))
        #expect(!KeyboardMapping.isModifierDown(.shift, flags: 0))
        // The same event twice (or one missed in between) reads the same each time.
        #expect(KeyboardMapping.isModifierDown(.shift, flags: shift | leftShift))
    }

    @Test("One Shift let go while the other is held is up")
    func eachSideOnItsOwn() {
        #expect(!KeyboardMapping.isModifierDown(.shift, flags: shift | rightShift))
        #expect(KeyboardMapping.isModifierDown(.rightShift, flags: shift | rightShift))
        #expect(KeyboardMapping.isModifierDown(.shift, flags: shift | leftShift | rightShift))
        #expect(KeyboardMapping.isModifierDown(.option, flags: option | leftOption))
        #expect(!KeyboardMapping.isModifierDown(.rightOption, flags: option | leftOption))
        #expect(KeyboardMapping.isModifierDown(.rightCommand, flags: command | rightCommand))
        #expect(!KeyboardMapping.isModifierDown(.control, flags: command | rightCommand))
    }

    @Test("Flags without the device bits fall back to the modifier as a whole")
    func wholeModifierFallback() {
        #expect(KeyboardMapping.isModifierDown(.shift, flags: shift))
        #expect(KeyboardMapping.isModifierDown(.rightShift, flags: shift))
        #expect(KeyboardMapping.isModifierDown(.control, flags: control))
        #expect(!KeyboardMapping.isModifierDown(.command, flags: shift))
    }

    @Test("Caps Lock is down while locked; other keys are never modifiers")
    func capsLockAndOthers() {
        #expect(KeyboardMapping.isModifierDown(.capsLock, flags: capsLock))
        #expect(!KeyboardMapping.isModifierDown(.capsLock, flags: shift | leftShift))
        #expect(!KeyboardMapping.isModifierDown(.a, flags: shift | leftShift))
    }
}
