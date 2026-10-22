/// 两个全局快捷键是不是同一个组合（键码和 Carbon 修饰键都相同）。另一个没设置时不算冲突。
public func hotKeyConflicts(keyCode: UInt32, modifiers: UInt32, otherKeyCode: UInt32?, otherModifiers: UInt32?) -> Bool {
    keyCode == otherKeyCode && modifiers == otherModifiers
}
