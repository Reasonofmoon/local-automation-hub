#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\system\ExplorerSelection.ahk
#Include ..\src\modules\FileOrganizer.ahk

global CapturedFileOrganizerPreview := ""

class FakeExplorerSelectionAdapter {
    __New(selectedItems := [], attributes := Map()) {
        this.selectedItems := selectedItems
        this.attributes := attributes
    }

    GetActiveSelectedItems() {
        return this.selectedItems
    }

    GetItemPath(item) {
        return item
    }

    GetAttributes(path) {
        key := StrLower(path)
        return this.attributes.Has(key) ? this.attributes[key] : FileGetAttrib(path)
    }
}

root := CreateTempDirectory()
try {
    sourceDirectory := root "\sources"
    secondSourceDirectory := root "\other-sources"
    folderSelection := root "\folder-selection"
    hiddenSource := sourceDirectory "\hidden.txt"
    systemSource := sourceDirectory "\system.txt"
    source := sourceDirectory "\report.txt"
    duplicateSource := secondSourceDirectory "\report.txt"
    DirCreate(sourceDirectory)
    DirCreate(secondSourceDirectory)
    DirCreate(folderSelection)
    FileAppend("content", source, "UTF-8")
    FileAppend("hidden", hiddenSource, "UTF-8")
    FileAppend("system", systemSource, "UTF-8")
    FileAppend("duplicate", duplicateSource, "UTF-8")

    attributes := Map(
        StrLower(hiddenSource), "H",
        StrLower(systemSource), "S"
    )
    selection := ExplorerSelection(FakeExplorerSelectionAdapter([
        source,
        StrUpper(source),
        folderSelection,
        hiddenSource,
        systemSource
    ], attributes))
    selectedPaths := selection.GetRegularFiles()
    AssertEqual(1, selectedPaths.Length, "filters folders, hidden and system selections")
    AssertEqual(source, selectedPaths[1], "normalizes and deduplicates selected paths")
    AssertThrows(() => ExplorerSelection(FakeExplorerSelectionAdapter()).GetRegularFiles(), "rejects empty Explorer selections")

    organizer := FileOrganizer(root "\state.ini")
    destinationDirectory := root "\2026\08"
    plan := organizer.BuildPlan([source], "2026-08-12")
    AssertEqual(root "\2026\08\2026-08-12_report.txt", plan[1].destination, "builds dated destination")
    AssertEqual(source, plan[1].source, "keeps the source path")
    AssertEqual("pending", plan[1].status, "marks a generated plan pending")
    AssertFalse(DirExist(destinationDirectory), "build plan does not create destination directories")
    AssertTrue(FileExist(source), "build plan does not move the source file")

    DirCreate(destinationDirectory)
    FileAppend("occupied", plan[1].destination, "UTF-8")
    collisionPlan := organizer.BuildPlan([source], "2026-08-12")
    AssertEqual(root "\2026\08\2026-08-12_report (2).txt", collisionPlan[1].destination, "avoids existing destination overwrites")

    multiplePlan := organizer.BuildPlan([source, duplicateSource], "2026-08-13")
    AssertEqual(root "\2026\08\2026-08-13_report.txt", multiplePlan[1].destination, "uses the first available destination")
    AssertEqual(root "\2026\08\2026-08-13_report (2).txt", multiplePlan[2].destination, "avoids collisions within one plan")
    AssertThrows(() => organizer.BuildPlan([source], "2026-8-12"), "requires an ISO date stamp")

    if !HasMethod(organizer, "ApplyPlan") || !HasMethod(organizer, "UndoLast") {
        AssertTrue(false, "file organizer exposes confirmed apply and one-step undo")
    } else {
    deniedPlan := organizer.BuildPlan([source], "2026-08-14")
    denied := organizer.ApplyPlan(deniedPlan, DenyFileOrganizerPlan)
    AssertTrue(InStr(CapturedFileOrganizerPreview, source) > 0, "apply preview includes the source")
    AssertTrue(InStr(CapturedFileOrganizerPreview, deniedPlan[1].destination) > 0, "apply preview includes the destination")
    AssertTrue(FileExist(source), "denial preserves source")
    AssertFalse(FileExist(deniedPlan[1].destination), "denial does not create destination")
    AssertEqual(0, denied.succeeded.Length, "denial performs no move")

    applied := organizer.ApplyPlan(deniedPlan, (*) => true)
    AssertEqual(1, applied.succeeded.Length, "confirmed plan records its successful move")
    AssertTrue(FileExist(deniedPlan[1].destination), "confirmed plan moves the file")
    AssertFalse(FileExist(source), "confirmed plan removes the source")
    AssertTrue(FileExist(root "\state.ini"), "successful move persists undo state")

    undoDenied := organizer.UndoLast((*) => false)
    AssertEqual(0, undoDenied.succeeded.Length, "undo denial restores nothing")
    AssertTrue(FileExist(deniedPlan[1].destination), "undo denial preserves moved file")

    FileAppend("occupied original", source, "UTF-8")
    undoCollision := organizer.UndoLast((*) => true)
    AssertTrue(undoCollision.aborted, "occupied original aborts undo before moving")
    AssertTrue(FileExist(deniedPlan[1].destination), "occupied original preserves moved file")
    FileDelete(source)
    undone := organizer.UndoLast((*) => true)
    AssertEqual(1, undone.succeeded.Length, "undo restores the saved move")
    AssertTrue(FileExist(source), "undo restores original path")
    AssertFalse(FileExist(deniedPlan[1].destination), "undo removes moved path")
    AssertFalse(FileExist(root "\state.ini"), "fully restored undo state is removed")
    AssertThrows(() => organizer.UndoLast((*) => true), "undo state is single use")

    occupiedDestination := root "\occupied.txt"
    FileAppend("occupied", occupiedDestination, "UTF-8")
    existingCollision := organizer.ApplyPlan([{ source: source, destination: occupiedDestination }], (*) => true)
    AssertTrue(existingCollision.aborted, "existing destination aborts the entire plan")
    AssertTrue(FileExist(source), "existing destination preserves source")

    inPlanDestination := root "\in-plan.txt"
    inPlanCollision := organizer.ApplyPlan([
        { source: source, destination: inPlanDestination },
        { source: duplicateSource, destination: StrUpper(inPlanDestination) }
    ], (*) => true)
    AssertTrue(inPlanCollision.aborted, "in-plan destination collision aborts the entire plan")
    AssertTrue(FileExist(source), "in-plan collision preserves first source")
    AssertTrue(FileExist(duplicateSource), "in-plan collision preserves second source")

    driftSource := sourceDirectory "\drift.txt"
    FileAppend("drift", driftSource, "UTF-8")
    driftPlan := organizer.BuildPlan([driftSource], "2027-08-15")
    FileDelete(driftSource)
    drifted := organizer.ApplyPlan(driftPlan, (*) => true)
    AssertTrue(drifted.aborted, "missing source aborts the plan after confirmation")
    AssertFalse(DirExist(root "\2027\08"), "drift abort does not create destination directories")

    partialDestination := root "\partial\first.txt"
    blockedParent := root "\not-a-directory"
    FileAppend("blocker", blockedParent, "UTF-8")
    partial := organizer.ApplyPlan([
        { source: source, destination: partialDestination },
        { source: duplicateSource, destination: blockedParent "\second.txt" }
    ], (*) => true)
    AssertEqual(1, partial.succeeded.Length, "partial failure keeps successful move")
    AssertEqual(1, partial.failed.Length, "partial failure records failed move")
    AssertTrue(FileExist(partialDestination), "partial failure moves available item")
    AssertTrue(FileExist(duplicateSource), "partial failure preserves unavailable item")
    partialUndo := organizer.UndoLast((*) => true)
    AssertEqual(1, partialUndo.succeeded.Length, "undo stores only successful partial moves")
    AssertTrue(FileExist(source), "partial undo restores successful item")
    AssertFalse(FileExist(partialDestination), "partial undo removes moved destination")
    }
} finally {
    DirDelete(root, 1)
}

ExitWithTestResult()

CreateTempDirectory() {
    root := A_Temp "\local-automation-hub-file-organizer-" A_TickCount "-" Random(100000, 999999)
    DirCreate(root)
    return root
}

DenyFileOrganizerPlan(preview) {
    global CapturedFileOrganizerPreview
    CapturedFileOrganizerPreview := preview
    return false
}
