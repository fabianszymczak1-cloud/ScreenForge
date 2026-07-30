import Foundation

struct UndoCommand {
    let undo: () -> Void
    let redo: () -> Void
}

@MainActor
final class UndoCoordinator {
    private var undoStack: [UndoCommand] = []
    private var redoStack: [UndoCommand] = []
    var limit: Int = 100
    private var isGrouping = false
    private var groupBuffer: [UndoCommand] = []

    func register(_ command: UndoCommand) {
        if isGrouping {
            groupBuffer.append(command)
            return
        }
        undoStack.append(command)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    func beginGroup() {
        isGrouping = true
        groupBuffer = []
    }

    func endGroup() {
        isGrouping = false
        guard !groupBuffer.isEmpty else { return }
        let commands = groupBuffer
        groupBuffer = []
        register(UndoCommand(
            undo: { commands.reversed().forEach { $0.undo() } },
            redo: { commands.forEach { $0.redo() } }
        ))
    }

    func undo() {
        guard let cmd = undoStack.popLast() else { return }
        cmd.undo()
        redoStack.append(cmd)
    }

    func redo() {
        guard let cmd = redoStack.popLast() else { return }
        cmd.redo()
        undoStack.append(cmd)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
}
